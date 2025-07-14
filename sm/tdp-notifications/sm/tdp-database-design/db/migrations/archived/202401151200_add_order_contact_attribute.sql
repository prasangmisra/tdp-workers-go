CREATE TABLE IF NOT EXISTS order_contact_attribute(
    FOREIGN KEY (contact_id) REFERENCES order_contact,
    PRIMARY KEY(id)
) INHERITS(contact_attribute);

CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_contact_id     UUID;
    v_create_domain   RECORD;
BEGIN

    SELECT id INTO v_contact_id FROM order_contact WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'reference id % not found in order_contact table',NEW.reference_id;
    END IF;

    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    -- thanks to the magic from inheritance, the contact table already
    -- contains the data, we just need to materialize it there.
    INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
    INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
    INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);

    -- we now signal the provisioning
    INSERT INTO provision_contact(
        contact_id,
        accreditation_id,
        tenant_customer_id,
        order_item_plan_ids
    ) VALUES(
                NEW.reference_id,
                v_create_domain.accreditation_id,
                v_create_domain.tenant_customer_id,
                ARRAY[NEW.id]
            ) ON CONFLICT (contact_id,accreditation_id)
        DO UPDATE
        SET order_item_plan_ids = provision_contact.order_item_plan_ids || EXCLUDED.order_item_plan_ids;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

