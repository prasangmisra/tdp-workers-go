-- drop unique host tenant_customer_id/name constraint
ALTER TABLE order_host
DROP CONSTRAINT IF EXISTS order_host_tenant_customer_id_name_key;

------------------------------------------------------------------------------------

-- function: ignore_address_if_host_already_exists()
-- description: skip addresses if address host already exists under the same tenant customer id
CREATE OR REPLACE FUNCTION ignore_address_if_host_already_exists() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM ONLY host h
    JOIN order_host oh ON oh.name = h.name
    WHERE oh.id = NEW.host_id AND oh.tenant_customer_id = h.tenant_customer_id;

    IF FOUND THEN
       RETURN NULL;
    END IF;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- skip addresses for existing host, existing addresses should be the source of truth.
CREATE OR REPLACE TRIGGER ignore_address_if_host_already_exists_tg
    BEFORE INSERT ON order_host_addr
    FOR EACH ROW EXECUTE PROCEDURE ignore_address_if_host_already_exists();

------------------------------------------------------------------------------------

-- function: plan_create_domain_provision_domain()
-- description: create a domain based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_domain          RECORD;
    v_create_domain   RECORD;
    v_pd_id           UUID;
BEGIN

    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    -- we now signal the provisioning
    WITH pd_ins AS (
        INSERT INTO provision_domain(
            name,
            registration_period,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            order_item_plan_ids
        ) VALUES(
            v_create_domain.domain_name,
            v_create_domain.registration_period,
            v_create_domain.accreditation_id,
            v_create_domain.accreditation_tld_id,
            v_create_domain.tenant_customer_id,
            ARRAY[NEW.id]
        ) RETURNING id
    )
    SELECT id INTO v_pd_id FROM pd_ins;

    -- insert contacts
    INSERT INTO provision_domain_contact(
        provision_domain_id,
        contact_id,
        contact_type_id
    )
    ( SELECT
          v_pd_id,
          order_contact_id,
          domain_contact_type_id
      FROM create_domain_contact
      WHERE create_domain_id = NEW.order_item_id
    );

    -- insert hosts
    INSERT INTO provision_domain_host(
        provision_domain_id,
        host_id
    )(
        SELECT
            v_pd_id,
            h.id
        FROM ONLY host h
        JOIN order_host oh ON oh.name = h.name
            JOIN create_domain_nameserver cdn ON cdn.host_id = oh.id
        WHERE cdn.create_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain SET is_complete = TRUE WHERE id = v_pd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;