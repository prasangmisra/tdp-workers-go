-- Alter provision_contact table
ALTER TABLE provision_contact
ADD COLUMN IF NOT EXISTS accreditation_tld_id UUID REFERENCES accreditation_tld,
ADD COLUMN IF NOT EXISTS domain_contact_type_id UUID REFERENCES domain_contact_type;


-- function: plan_create_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain             RECORD;
    v_create_domain_contact     RECORD;
    _thin_registry              BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    SELECT * INTO v_create_domain_contact
    FROM create_domain_contact
    WHERE order_contact_id = NEW.reference_id
      AND create_domain_id = NEW.order_item_id;

    PERFORM TRUE
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    -- Check if the registry is thin
    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.is_thin_registry', 
        p_accreditation_tld_id => v_create_domain.accreditation_tld_id
    ) INTO _thin_registry;

    -- Check if contact is already provisioned
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_create_domain.accreditation_id;

    -- Check if at least one contact type specified for this contact is supported
    SELECT BOOL_OR(is_contact_type_supported_for_tld(
            v_create_domain_contact.domain_contact_type_id,
        v_create_domain.accreditation_tld_id
    )) INTO _supported_contact_type;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN
        
        UPDATE create_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            accreditation_tld_id,
            domain_contact_type_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
            NEW.reference_id,
            v_create_domain.accreditation_id,
            v_create_domain.accreditation_tld_id,
            v_create_domain_contact.domain_contact_type_id,
            v_create_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_create_domain.order_metadata
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_update_domain_contact     RECORD;
    _contact_exists             BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _thin_registry              BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;


    SELECT * INTO v_update_domain_contact
    FROM (
        SELECT domain_contact_type_id FROM update_domain_contact
        WHERE order_contact_id = NEW.reference_id
        AND update_domain_id = NEW.order_item_id

        UNION

        SELECT domain_contact_type_id FROM update_domain_add_contact
        WHERE order_contact_id = NEW.reference_id
        AND update_domain_id = NEW.order_item_id
    ) combined_results;

    -- Check if trying to add a contact type that already exists and is not being removed
    IF EXISTS (
        SELECT 1
        FROM update_domain_add_contact udac
        JOIN domain_contact dc ON dc.domain_id = v_update_domain.domain_id
                              AND dc.domain_contact_type_id = udac.domain_contact_type_id
        WHERE udac.update_domain_id = NEW.order_item_id
          AND udac.order_contact_id = NEW.reference_id
          AND NOT EXISTS (
            SELECT 1 FROM update_domain_rem_contact udrc
            WHERE udrc.update_domain_id = NEW.order_item_id
              AND udrc.domain_contact_type_id = udac.domain_contact_type_id
          )
    ) THEN
        RAISE EXCEPTION 'Cannot add contact type because it already exists and is not being removed';
    END IF;

    SELECT TRUE INTO _contact_exists
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    -- Check if the registry is thin
    SELECT get_tld_setting(
        p_key=>'tld.lifecycle.is_thin_registry',
        p_accreditation_tld_id=>v_update_domain.accreditation_tld_id)
    INTO _thin_registry;

    -- Check if contact is already provisioned
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_update_domain.accreditation_id;

    -- Check if at least one contact type specified for this contact is supported
    SELECT BOOL_OR(is_contact_type_supported_for_tld(
        v_update_domain_contact.domain_contact_type_id,
        v_update_domain.accreditation_tld_id
    )) INTO _supported_contact_type;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN

        UPDATE update_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            accreditation_tld_id,
            domain_contact_type_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
            NEW.reference_id,
            v_update_domain.accreditation_id,
            v_update_domain.accreditation_tld_id,
            v_update_domain_contact.domain_contact_type_id,
            v_update_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_update_domain.order_metadata
        );
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            error_message TEXT;
        BEGIN
            -- Capture the error message
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;

            -- Update the plan with the captured error message
            UPDATE update_domain_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
END;
$$ LANGUAGE plpgsql;


--
-- function: jsonb_get_rdp_contact_by_id()
-- description: returns a jsonb containing all the attributes of a contact filtered according to allowed data elements
--
CREATE OR REPLACE FUNCTION jsonb_select_contact_data_by_id(
    p_id UUID,
    selected_elements TEXT[] DEFAULT '{}'
) RETURNS JSONB AS $$
DECLARE
    result JSONB;
    attr_result JSONB;
    postal_result JSONB;
BEGIN
    SELECT jsonb_build_object(
                   'id', c.id,
                   'short_id', c.short_id,
                   'contact_type', tc_name_from_id('contact_type', c.type_id),
                   'title', CASE WHEN 'title' = ANY(selected_elements) THEN c.title END,
                   'org_reg', CASE WHEN 'org_reg' = ANY(selected_elements) THEN c.org_reg END,
                   'org_vat', CASE WHEN 'org_vat' = ANY(selected_elements) THEN c.org_vat END,
                   'org_duns', CASE WHEN 'org_duns' = ANY(selected_elements) THEN c.org_duns END,
                   'tenant_customer_id', CASE WHEN 'tenant_customer_id' = ANY(selected_elements) THEN c.tenant_customer_id END,
                   'email', CASE WHEN 'email' = ANY(selected_elements) THEN c.email END,
                   'phone', CASE WHEN 'phone' = ANY(selected_elements) THEN c.phone END,
                   'fax', CASE WHEN 'fax' = ANY(selected_elements) THEN c.fax END,
                   'country', CASE WHEN 'country' = ANY(selected_elements) THEN c.country END,
                   'language', CASE WHEN 'language' = ANY(selected_elements) THEN c.language END,
                   'documentation', CASE WHEN 'documentation' = ANY(selected_elements) THEN c.documentation END,
                   'tags', c.tags,
                   'metadata', c.metadata
           ) INTO result
    FROM ONLY contact c
    WHERE c.id = p_id;

    -- Skip further processing if contact not found
    IF result IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT jsonb_object_agg(
                   an.name,
                   CASE WHEN an.name = ANY(selected_elements) THEN ca.value END
           ) INTO attr_result
    FROM ONLY contact_attribute ca
             JOIN attribute an ON an.id = ca.attribute_id
    WHERE ca.contact_id = p_id;

    -- Get postal data with direct filtering
    SELECT jsonb_build_object('contact_postals', jsonb_agg(
            jsonb_build_object(
                    'is_international', cp.is_international,
                    'first_name', CASE WHEN 'first_name' = ANY(selected_elements) THEN cp.first_name END,
                    'last_name', CASE WHEN 'last_name' = ANY(selected_elements) THEN cp.last_name END,
                    'org_name', CASE WHEN 'org_name' = ANY(selected_elements) THEN cp.org_name END,
                    'address1', CASE WHEN 'address1' = ANY(selected_elements) THEN cp.address1 END,
                    'address2', CASE WHEN 'address2' = ANY(selected_elements) THEN cp.address2 END,
                    'address3', CASE WHEN 'address3' = ANY(selected_elements) THEN cp.address3 END,
                    'city', CASE WHEN 'city' = ANY(selected_elements) THEN cp.city END,
                    'postal_code', CASE WHEN 'postal_code' = ANY(selected_elements) THEN cp.postal_code END,
                    'state', CASE WHEN 'state' = ANY(selected_elements) THEN cp.state END
            ) ORDER BY cp.is_international ASC
                                                 )) INTO postal_result
    FROM ONLY contact_postal cp
    WHERE cp.contact_id = p_id;

    -- Combine results
    RETURN result || COALESCE(attr_result, '{}'::JSONB) || COALESCE(postal_result, '{}'::JSONB);
END;
$$ LANGUAGE plpgsql STABLE;

-- function: provision_contact_job()
-- description: creates the job to create the contact
CREATE OR REPLACE FUNCTION provision_contact_job() RETURNS TRIGGER AS $$
DECLARE
    v_contact       RECORD;
    v_rdp_enabled   BOOLEAN;
BEGIN

    SELECT get_tld_setting(
        p_key => 'tld.order.rdp_enabled',
        p_accreditation_tld_id => NEW.accreditation_tld_id
   ) INTO v_rdp_enabled;

    SELECT
        NEW.id AS provision_contact_id,
        NEW.tenant_customer_id AS tenant_customer_id,
        CASE WHEN v_rdp_enabled THEN
            jsonb_select_contact_data_by_id(
                c.id,
                CASE
                WHEN vat.tld_id IS NOT NULL THEN
                    get_domain_data_elements_for_permission(
                        p_tld_id => vat.tld_id,
                        p_data_element_parent_name => tc_name_from_id('domain_contact_type', NEW.domain_contact_type_id),
                        p_permission_name => 'transmit_to_registry'
                    )
                END
            )
        ELSE
            jsonb_get_contact_by_id(c.id)
        END AS contact,
        TO_JSONB(a.*) AS accreditation,
        NEW.pw AS pw,
        NEW.order_metadata AS metadata
    INTO v_contact
    FROM ONLY contact c
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    LEFT JOIN v_accreditation_tld vat ON vat.accreditation_id = NEW.accreditation_id
    AND vat.accreditation_tld_id = NEW.accreditation_tld_id
    WHERE c.id=NEW.contact_id;

    UPDATE provision_contact SET job_id=job_submit(
        NEW.tenant_customer_id,
        'provision_contact_create',
        NEW.id,
        TO_JSONB(v_contact.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
