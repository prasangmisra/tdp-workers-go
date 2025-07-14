-- domain create
-- replace foreign key constraint with trigger to check against contact/order_contact.
-- and update plan_create_domain_provision_contact function.

ALTER TABLE create_domain_contact
DROP CONSTRAINT IF EXISTS create_domain_contact_order_contact_id_fkey;
-----------------------------------------------------------------------------

-- function: order_prevent_if_create_domain_contact_does_not_exist
-- description: Simulates a foreign key constraint for the order_contact_id column
-- by ensuring it references an existing ID in either the contact or order_contact table.
CREATE OR REPLACE FUNCTION order_prevent_if_create_domain_contact_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT
            1
        FROM
            ONLY contact c
            JOIN v_order_create_domain cd ON cd.order_item_id = NEW.create_domain_id
        WHERE
            c.id = NEW.order_contact_id
            AND c.tenant_customer_id = cd.tenant_customer_id
            AND c.deleted_date IS NULL)
    AND NOT EXISTS (
        SELECT
            1
        FROM
            ONLY order_contact
        WHERE id = NEW.order_contact_id
        AND deleted_date IS NULL)
    THEN
        RAISE EXCEPTION 'order_contact_id % does not exist in either contact or order_contact table.', NEW.order_contact_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS order_prevent_if_create_domain_contact_does_not_exist_tg ON create_domain_contact;
-----------------------------------------------------------------------------

CREATE TRIGGER order_prevent_if_create_domain_contact_does_not_exist_tg
    BEFORE INSERT ON create_domain_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
    EXECUTE PROCEDURE order_prevent_if_create_domain_contact_does_not_exist();

-----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS plan_create_domain_provision_contact_tg ON create_domain_plan;
DROP FUNCTION IF EXISTS plan_create_domain_provision_contact;
-----------------------------------------------------------------------------

-- function: plan_create_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain         RECORD;
    _contact_exists         BOOLEAN;
    _contact_provisioned    BOOLEAN;
BEGIN
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

    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
    AND pc.accreditation_id = v_create_domain.accreditation_id;

    IF NOT FOUND THEN
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
        );
    ELSE
        -- contact has already been provisioned, we can mark this as complete.
        UPDATE create_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-----------------------------------------------------------------------------
CREATE TRIGGER plan_create_domain_provision_contact_tg
    AFTER UPDATE ON create_domain_plan
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','contact')
    )
    EXECUTE PROCEDURE plan_create_domain_provision_contact();

-----------------------------------------------------------------------------

-- domain update
-- replace foreign key constraint with trigger to check against contact/order_contact.
-- and update plan_update_domain_provision_contact function.

ALTER TABLE update_domain_contact
DROP CONSTRAINT If EXISTS update_domain_contact_order_contact_id_fkey;
-----------------------------------------------------------------------------

-- function: order_prevent_if_update_domain_contact_does_not_exist
-- description: Simulates a foreign key constraint for the order_contact_id column
-- by ensuring it references an existing ID in either the contact or order_contact table.
CREATE OR REPLACE FUNCTION order_prevent_if_update_domain_contact_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT
            1
        FROM
            ONLY contact c
            JOIN v_order_update_domain cd ON cd.order_item_id = NEW.update_domain_id
        WHERE
            c.id = NEW.order_contact_id
            AND c.tenant_customer_id = cd.tenant_customer_id
            AND c.deleted_date IS NULL)
    AND NOT EXISTS (
        SELECT
            1
        FROM
            ONLY order_contact
        WHERE id = NEW.order_contact_id
        AND deleted_date IS NULL)
    THEN
        RAISE EXCEPTION 'order_contact_id % does not exist in either contact or order_contact table.', NEW.order_contact_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS order_prevent_if_update_domain_contact_does_not_exist_tg ON update_domain_contact;
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
CREATE TRIGGER order_prevent_if_update_domain_contact_does_not_exist_tg
    BEFORE INSERT ON update_domain_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
    EXECUTE PROCEDURE order_prevent_if_update_domain_contact_does_not_exist();
-----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS plan_update_domain_provision_contact_tg ON update_domain_plan;
DROP FUNCTION IF EXISTS plan_update_domain_provision_contact;

-----------------------------------------------------------------------------

-- function: plan_update_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain         RECORD;
    _contact_exists         BOOLEAN;
    _contact_provisioned    BOOLEAN;
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

    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
    AND pc.accreditation_id = v_update_domain.accreditation_id;

    IF NOT FOUND THEN
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids
        ) VALUES(
            NEW.reference_id,
            v_update_domain.accreditation_id,
            v_update_domain.tenant_customer_id,
            ARRAY[NEW.id]
        );
    ELSE
        -- contact has already been provisioned, we can mark this as complete.
        UPDATE update_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-----------------------------------------------------------------------------
CREATE TRIGGER plan_update_domain_provision_contact_tg
    AFTER UPDATE ON update_domain_plan
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','contact')
    )
    EXECUTE PROCEDURE plan_update_domain_provision_contact();
