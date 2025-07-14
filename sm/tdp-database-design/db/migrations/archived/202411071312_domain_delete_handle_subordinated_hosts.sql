INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key
)
VALUES
(
    'provision_domain_delete_host',
    'Deletes a domain host',
    'provision_domain_delete_host',
    'provision_status',
    'status_id',
    'WorkerJobHostProvision'
)
ON CONFLICT DO NOTHING;

ALTER TABLE order_item_delete_domain ADD COLUMN IF NOT EXISTS hosts TEXT[];

ALTER TABLE provision_domain_delete ADD COLUMN IF NOT EXISTS is_complete BOOLEAN DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS provision_domain_delete_host(
    id                            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    provision_domain_delete_id    UUID NOT NULL REFERENCES provision_domain_delete
    ON DELETE CASCADE,
    host_name                     TEXT NOT NULL,
    UNIQUE(provision_domain_delete_id,host_name)
) INHERITS(class.audit,class.provision);

CREATE OR REPLACE FUNCTION provision_domain_delete_success() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.in_redemption_grace_period THEN
        INSERT INTO domain_rgp_status(
            domain_id,
            status_id
        ) VALUES (
                     NEW.domain_id,
                     tc_id_from_name('rgp_status', 'redemption_grace_period')
                 );

        UPDATE domain
        SET deleted_date = NOW()
        WHERE id = NEW.domain_id;
    ELSE
        DELETE FROM provision_host
        WHERE domain_id = NEW.domain_id;

        DELETE FROM domain
        WHERE id = NEW.domain_id;

        DELETE FROM provision_domain
        WHERE domain_name = NEW.domain_name;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION provision_domain_delete_host_success() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM ONLY host WHERE name=NEW.host_name;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION plan_delete_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_domain RECORD;
    v_pd_id         UUID;
    v_host          RECORD;
    _host           TEXT;
BEGIN
    SELECT * INTO v_delete_domain
    FROM v_order_delete_domain
    WHERE order_item_id = NEW.order_item_id;

    WITH pd_ins AS (
        INSERT INTO provision_domain_delete(
                                            domain_id,
                                            domain_name,
                                            accreditation_id,
                                            tenant_customer_id,
                                            order_metadata,
                                            order_item_plan_ids
            ) VALUES(
                        v_delete_domain.domain_id,
                        v_delete_domain.domain_name,
                        v_delete_domain.accreditation_id,
                        v_delete_domain.tenant_customer_id,
                        v_delete_domain.order_metadata,
                        ARRAY[NEW.id]
                    ) RETURNING id
    ) SELECT id INTO v_pd_id FROM pd_ins;

    -- Validate if any of the subordinated hosts belong to customer and associated with active domains in database
    IF EXISTS (
        SELECT 1
        FROM host h
                 JOIN domain_host dh ON dh.host_id = h.id
        WHERE h.name = ANY(v_delete_domain.hosts)
    ) THEN
        RAISE EXCEPTION 'Host(s) % are associated with active domain(s)', v_delete_domain.hosts;
    END IF;

    --  insert hosts
    IF v_delete_domain.hosts IS NOT NULL THEN
        INSERT INTO provision_domain_delete_host(
            provision_domain_delete_id,
            host_name,
            tenant_customer_id,
            order_metadata
        )
        SELECT v_pd_id, UNNEST(v_delete_domain.hosts), v_delete_domain.tenant_customer_id, v_delete_domain.order_metadata;
    END IF;

    UPDATE provision_domain_delete
    SET is_complete = TRUE
    WHERE id = v_pd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS provision_domain_delete_host_success_tg ON provision_domain_delete_host;
CREATE TRIGGER provision_domain_delete_host_success_tg
    AFTER UPDATE ON provision_domain_delete_host
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
    ) EXECUTE PROCEDURE provision_domain_delete_host_success();

DROP TRIGGER IF EXISTS provision_domain_delete_job_tg ON provision_domain_delete;
CREATE TRIGGER provision_domain_delete_job_tg
    AFTER UPDATE ON provision_domain_delete
    FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete
        AND NEW.is_complete
        AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
    ) EXECUTE PROCEDURE provision_domain_delete_job();

DROP VIEW IF EXISTS v_order_delete_domain;
CREATE OR REPLACE VIEW v_order_delete_domain AS
SELECT
    dd.id AS order_item_id,
    dd.order_id AS order_id,
    dd.accreditation_tld_id,
    o.metadata AS order_metadata,
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
    d.id   AS domain_id,
    dd.hosts
FROM order_item_delete_domain dd
         JOIN "order" o ON o.id=dd.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
         JOIN v_accreditation_tld at ON at.accreditation_tld_id = dd.accreditation_tld_id
         JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=dd.name
;


CREATE OR REPLACE FUNCTION provision_domain_delete_job() RETURNS TRIGGER AS $$
DECLARE
    v_delete        RECORD;
    _pddh           RECORD;
    _parent_job_id  UUID;
BEGIN

    SELECT
        NEW.id AS provision_domain_delete_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pd.domain_name AS domain_name,
        pd.order_metadata AS metadata
    INTO v_delete
    FROM provision_domain_delete pd
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pd.id = NEW.id;

    PERFORM TRUE
    FROM provision_domain_delete_host
    WHERE provision_domain_delete_id = NEW.id;

    IF FOUND THEN
        SELECT job_create(
                       v_delete.tenant_customer_id,
                       'provision_domain_delete',
                       NEW.id,
                       TO_JSONB(v_delete.*)
               ) INTO _parent_job_id;

        UPDATE provision_domain_delete SET job_id= _parent_job_id WHERE id=NEW.id;

        FOR _pddh IN
            SELECT
                pddh.id AS provision_host_delete_id,
                pddh.host_name,
                TO_JSONB(a.*) AS accreditation,
                NEW.tenant_customer_id as tenant_customer_id,
                get_tld_setting(
                        p_key=>'tld.order.host_delete_rename_allowed',
                        p_tld_name=>tld_part(pddh.host_name),
                        p_tenant_id=>a.tenant_id
                )::BOOL AS host_delete_rename_allowed,
                get_tld_setting(
                        p_key=>'tld.order.host_delete_rename_domain',
                        p_tld_name=>tld_part(pddh.host_name),
                        p_tenant_id=>a.tenant_id
                )::TEXT AS host_delete_rename_domain,
                TO_JSONB(a.*) AS accreditation,
                NEW.order_metadata AS metadata
            FROM provision_domain_delete_host pddh
                     JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
            WHERE pddh.provision_domain_delete_id = NEW.id
            LOOP
                UPDATE provision_domain_delete_host SET job_id=job_submit(
                        v_delete.tenant_customer_id,
                        'provision_domain_delete_host',
                        _pddh.provision_host_delete_id,
                        TO_JSONB(_pddh.*),
                        _parent_job_id
                                                               )
                WHERE id=_pddh.provision_host_delete_id;
            END LOOP;
    ELSE
        UPDATE provision_domain_delete SET job_id=job_submit(
                v_delete.tenant_customer_id,
                'provision_domain_delete',
                NEW.id,
                TO_JSONB(v_delete.*)
                                                  ) WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
