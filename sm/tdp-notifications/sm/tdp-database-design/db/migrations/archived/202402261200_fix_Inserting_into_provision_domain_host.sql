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
    ) (
        SELECT
            v_pd_id,
            h.id
        FROM ONLY host h
        WHERE
            h.name IN (
                SELECT name
                FROM create_domain_nameserver
                WHERE create_domain_id = NEW.order_item_id
            )
          AND tenant_customer_id = v_create_domain.tenant_customer_id
    );

    UPDATE provision_domain SET is_complete = TRUE WHERE id = v_pd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;