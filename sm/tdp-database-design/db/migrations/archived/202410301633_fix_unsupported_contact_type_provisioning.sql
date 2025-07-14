CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain             RECORD;
    _contact_exists             BOOLEAN;
    _thin_registry              BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

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
        p_key => 'tld.lifecycle.is_thin_registry', 
        p_tld_id => v_create_domain.tld_id, 
        p_tenant_id => v_create_domain.tenant_id
    ) INTO _thin_registry;

    -- Check if contact is already provisioned
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_create_domain.accreditation_id;

    -- Check if at least one contact type specified for this contact is supported
    SELECT BOOL_OR(supported_contact_type) INTO _supported_contact_type
    FROM (
        SELECT is_contact_type_supported_for_tld(
            domain_contact_type_id,
            v_create_domain.accreditation_tld_id
        ) AS supported_contact_type
        FROM create_domain_contact
        WHERE order_contact_id = NEW.reference_id
            AND create_domain_id = NEW.order_item_id
    ) AS sct;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN
        
        UPDATE create_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
            NEW.reference_id,
            v_create_domain.accreditation_id,
            v_create_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_create_domain.order_metadata
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    _contact_exists             BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _thin_registry              BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

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
                   p_tld_id=>vat.tld_id,
                   p_tenant_id=>vtc.tenant_id
           )
    INTO _thin_registry
    FROM v_tenant_customer vtc
             JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_update_domain.accreditation_tld_id
    WHERE vtc.id = v_update_domain.tenant_customer_id;

    -- Check if contact is already provisioned
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_update_domain.accreditation_id;

    -- Check if at least one contact type specified for this contact is supported
    SELECT BOOL_OR(supported_contact_type) INTO _supported_contact_type
    FROM (
        SELECT is_contact_type_supported_for_tld(
            domain_contact_type_id,
            v_update_domain.accreditation_tld_id
        ) AS supported_contact_type
        FROM update_domain_contact
        WHERE order_contact_id = NEW.reference_id
            AND update_domain_id = NEW.order_item_id
    ) AS sct;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN

        UPDATE update_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
            NEW.reference_id,
            v_update_domain.accreditation_id,
            v_update_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_update_domain.order_metadata
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

