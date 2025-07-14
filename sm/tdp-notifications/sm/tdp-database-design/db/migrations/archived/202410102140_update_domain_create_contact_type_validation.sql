UPDATE attr_key SET default_value = '{}' WHERE name = 'optional_contact_types';

-- function: plan_create_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain             RECORD;
    _contact_exists             BOOLEAN;
    _thin_registry              BOOLEAN;
    _contact_provisioned        BOOLEAN;
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

    IF FOUND OR _thin_registry THEN
        -- Skip contact provision if contact is already provisioned or if the registry is thin
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
        ) (
            SELECT
                NEW.reference_id,
                v_create_domain.accreditation_id,
                v_create_domain.tenant_customer_id,
                ARRAY[NEW.id],
                v_create_domain.order_metadata
            FROM create_domain_contact
            WHERE order_contact_id = NEW.reference_id
            AND create_domain_id = NEW.order_item_id
            AND is_contact_type_supported_for_tld(domain_contact_type_id, v_create_domain.accreditation_tld_id)
        ) ON CONFLICT (contact_id,accreditation_id) DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain         RECORD;
    _contact_exists         BOOLEAN;
    _contact_provisioned    BOOLEAN;
    _thin_registry          BOOLEAN;
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

    SELECT get_tld_setting(
                   p_key=>'tld.lifecycle.is_thin_registry',
                   p_tld_id=>vat.tld_id,
                   p_tenant_id=>vtc.tenant_id
           )
    INTO _thin_registry
    FROM v_tenant_customer vtc
             JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_update_domain.accreditation_tld_id
    WHERE vtc.id = v_update_domain.tenant_customer_id;

    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_update_domain.accreditation_id;

    IF FOUND OR _thin_registry THEN
        -- contact has already been provisioned, we can mark this as complete.
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
        ) (
            SELECT
                NEW.reference_id,
                v_update_domain.accreditation_id,
                v_update_domain.tenant_customer_id,
                ARRAY[NEW.id],
                v_update_domain.order_metadata
            FROM update_domain_contact
            WHERE order_contact_id = NEW.reference_id
            AND update_domain_id = NEW.order_item_id
            AND is_contact_type_supported_for_tld(domain_contact_type_id, v_update_domain.accreditation_tld_id)
        ) ON CONFLICT (contact_id,accreditation_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
