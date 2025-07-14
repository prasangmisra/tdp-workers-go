-- update tables to add auto_renew column
ALTER TABLE domain
ADD COLUMN IF NOT EXISTS auto_renew BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE order_item_create_domain
ADD COLUMN IF NOT EXISTS auto_renew BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE order_item_update_domain
ADD COLUMN IF NOT EXISTS auto_renew BOOLEAN;

ALTER TABLE provision_domain
ADD COLUMN IF NOT EXISTS auto_renew BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE provision_domain_update
ADD COLUMN IF NOT EXISTS auto_renew BOOLEAN;


------------------------------------------------
DROP VIEW IF EXISTS v_order_create_domain;
CREATE OR REPLACE VIEW v_order_create_domain AS
SELECT
    cd.id AS order_item_id,
    cd.order_id AS order_id,
    cd.accreditation_tld_id,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name,
    at.provider_name,
    at.provider_instance_id,
    at.provider_instance_name,
    at.tld_id AS tld_id,
    at.tld_name AS tld_name,
    at.accreditation_id,
    cd.name AS domain_name,
    cd.registration_period AS registration_period,
    cd.auto_renew
FROM order_item_create_domain cd
    JOIN "order" o ON o.id=cd.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = cd.accreditation_tld_id
;


DROP VIEW IF EXISTS v_order_update_domain;
CREATE OR REPLACE VIEW v_order_update_domain AS
SELECT
    ud.id AS order_item_id,
    ud.order_id AS order_id,
    ud.accreditation_tld_id,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name,
    at.provider_name,
    at.provider_instance_id,
    at.provider_instance_name,
    at.tld_id AS tld_id,
    at.tld_name AS tld_name,
    at.accreditation_id,
    d.name AS domain_name,
    d.id AS domain_id,
    ud.auth_info,
    ud.hosts,
    ud.auto_renew
FROM order_item_update_domain ud
    JOIN "order" o ON o.id=ud.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = ud.accreditation_tld_id
    JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=ud.name
;



-- function: provision_domain_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_success() RETURNS TRIGGER AS $$
DECLARE
    s_id UUID;
BEGIN

    SELECT id
    INTO s_id
    FROM domain_status ds
    WHERE ds.name = 'active';

    -- domain
    INSERT INTO domain(
        id,
        tenant_customer_id,
        accreditation_tld_id,
        name,
        auth_info,
        roid,
        ry_created_date,
        ry_expiry_date,
        expiry_date,
        status_id,
        auto_renew
    ) (
        SELECT
            pd.id,    -- domain id
            pd.tenant_customer_id,
            pd.accreditation_tld_id,
            pd.name,
            pd.pw,
            pd.roid,
            COALESCE(pd.ry_created_date,pd.created_date),
            COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%d years',pd.registration_period)::INTERVAL),
            COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%d years',pd.registration_period)::INTERVAL),
            s_id as status_id,
            pd.auto_renew
        FROM provision_domain pd
        WHERE id = NEW.id
    );

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            pdc.provision_domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_id = NEW.id
    );


    -- host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            provision_domain_id,
            host_id
        FROM provision_domain_host
        WHERE provision_domain_id = NEW.id
    );


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;




--
-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
DECLARE
    v_domain_id UUID;
BEGIN

    SELECT id INTO v_domain_id FROM domain WHERE name = NEW.name;

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            v_domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_update_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
          DO UPDATE SET contact_id = EXCLUDED.contact_id;

    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            v_domain_id,
            h.id
        FROM ONLY host h
        WHERE h.name IN (SELECT UNNEST(NEW.hosts))
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete removed hosts
    DELETE FROM
        domain_host dh
        USING
            host h
    WHERE
        NEW.hosts IS NOT NULL
      AND h.name NOT IN (SELECT UNNEST(NEW.hosts))
      AND dh.domain_id = v_domain_id
      AND dh.host_id = h.id;

    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew)
    WHERE d.id = v_domain_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



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
        auto_renew,
        order_item_plan_ids
    ) VALUES(
        v_create_domain.domain_name,
        v_create_domain.registration_period,
        v_create_domain.accreditation_id,
        v_create_domain.accreditation_tld_id,
        v_create_domain.tenant_customer_id,
        v_create_domain.auto_renew,
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
        JOIN order_host oh ON oh.name = h.name
            JOIN create_domain_nameserver cdn ON cdn.host_id = oh.id
        WHERE cdn.create_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain SET is_complete = TRUE WHERE id = v_pd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



--
-- function: plan_update_domain_provision_domain()
-- description: update a domain based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_pd_id                     UUID;
BEGIN

    -- order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- we now signal the provisioning
    WITH pd_ins AS (
    INSERT INTO provision_domain_update(
        name,
        auth_info,
        hosts,
        accreditation_id,
        accreditation_tld_id,
        tenant_customer_id,
        auto_renew,
        order_item_plan_ids
    ) VALUES(
        v_update_domain.domain_name,
        v_update_domain.auth_info,
        v_update_domain.hosts,
        v_update_domain.accreditation_id,
        v_update_domain.accreditation_tld_id,
        v_update_domain.tenant_customer_id,
        v_update_domain.auto_renew,
        ARRAY[NEW.id]
        ) RETURNING id
        )
    SELECT id INTO v_pd_id FROM pd_ins;

    -- insert contacts
    INSERT INTO provision_domain_update_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )
        (
            SELECT
                v_pd_id,
                order_contact_id,
                domain_contact_type_id
            FROM update_domain_contact
            WHERE update_domain_id = NEW.order_item_id
        );

    UPDATE provision_domain_update SET is_complete = TRUE WHERE id = v_pd_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
