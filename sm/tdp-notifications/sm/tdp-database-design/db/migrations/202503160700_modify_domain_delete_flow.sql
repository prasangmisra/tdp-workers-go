-- Delete provision_domain_expiry_date_check job type
DELETE FROM job_type WHERE name = 'provision_domain_expiry_date_check';

-- Insert setup_domain_renew & setup_domain_delete job types
INSERT INTO job_type(
    name,
    descr,
    reference_status_table,
    reference_status_column,
    routing_key
) VALUES (
    'setup_domain_renew',
    'Sets up domain renew job',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'setup_domain_delete',
    'Sets up domain delete job',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
) ON CONFLICT DO NOTHING;


-- Update provision_domain_delete_job_tg trigger to delete the domain
DROP TRIGGER IF EXISTS provision_domain_delete_job_tg ON provision_domain_delete;
CREATE TRIGGER provision_domain_delete_job_tg
  AFTER INSERT ON provision_domain_delete
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_delete_job();


-- Modify provision_domain_delete table: remove is_complete column and add hosts column
ALTER TABLE provision_domain_delete
    DROP COLUMN IF EXISTS is_complete;

ALTER TABLE provision_domain_delete
    ADD COLUMN IF NOT EXISTS hosts TEXT[];

-- function: plan_delete_domain_provision()
-- description: deletes a domain based on the plan
CREATE OR REPLACE FUNCTION plan_delete_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_domain RECORD;
    v_pd_id         UUID;
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

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_delete_job()
-- description: creates the job to delete the domain
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

    SELECT job_create(
        v_delete.tenant_customer_id,
        'provision_domain_delete',
        NEW.id,
        TO_JSONB(v_delete.*)
    ) INTO _parent_job_id;

    UPDATE provision_domain_delete SET job_id= _parent_job_id WHERE id=NEW.id;

    PERFORM job_submit(
        v_delete.tenant_customer_id,
        'setup_domain_delete',
        NEW.id,
        TO_JSONB(v_delete.*),
        _parent_job_id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_hosts_delete_job()
-- description: creates the job to delete the domain hosts
CREATE OR REPLACE FUNCTION provision_domain_hosts_delete_job() RETURNS TRIGGER AS $$
DECLARE
    _host_name      TEXT;
    _pddh_id        UUID;
    _pddh           RECORD;
BEGIN
    -- Validate if any of the subordinated hosts belong to customer and associated with active domains in database
    IF EXISTS (
        SELECT 1
        FROM host h
        JOIN domain_host dh ON dh.host_id = h.id
        WHERE h.name = ANY(NEW.hosts)
    ) THEN
        UPDATE job
        SET result_message = 'Host(s) are associated with active domain(s)',
            status_id = tc_id_from_name('job_status', 'failed')
        WHERE id = NEW.job_id;

        RETURN NEW;
    END IF;

    -- Insert hosts and submit job for each domain host deletion
    IF NEW.hosts IS NOT NULL THEN
        FOR _host_name IN SELECT UNNEST(NEW.hosts) LOOP
            WITH inserted AS (
                INSERT INTO provision_domain_delete_host(
                    provision_domain_delete_id,
                    host_name,
                    tenant_customer_id,
                    order_metadata
                )
                VALUES (NEW.id, _host_name, NEW.tenant_customer_id, NEW.order_metadata)
                RETURNING id
            )
            SELECT id FROM inserted INTO _pddh_id;

            SELECT
                NEW.id AS provision_domain_delete_id,
                _host_name AS host_name,
                NEW.tenant_customer_id as tenant_customer_id,
                get_tld_setting(
                    p_key=>'tld.order.host_delete_rename_allowed',
                    p_tld_name=>tld_part(_host_name),
                    p_tenant_id=>a.tenant_id
                )::BOOL AS host_delete_rename_allowed,
                get_tld_setting(
                    p_key=>'tld.order.host_delete_rename_domain',
                    p_tld_name=>tld_part(_host_name),
                    p_tenant_id=>a.tenant_id
                )::TEXT AS host_delete_rename_domain,
                TO_JSONB(a.*) AS accreditation,
                NEW.order_metadata AS metadata
            INTO _pddh
            FROM v_accreditation a
            WHERE a.accreditation_id = NEW.accreditation_id;

            UPDATE provision_domain_delete_host SET job_id=job_submit(
                NEW.tenant_customer_id,
                'provision_domain_delete_host',
                _pddh_id,
                TO_JSONB(_pddh.*),
                NEW.job_id
            )
            WHERE id = _pddh_id;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Add provision_domain_hosts_delete_job_tg trigger to delete the domain hosts
DROP TRIGGER IF EXISTS provision_domain_hosts_delete_job_tg ON provision_domain_delete;
CREATE TRIGGER provision_domain_hosts_delete_job_tg
  AFTER UPDATE ON provision_domain_delete
  FOR EACH ROW WHEN (
    OLD.hosts IS DISTINCT FROM NEW.hosts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_hosts_delete_job();


-- function: provision_domain_renew_job()
-- description: creates the job to renew the domain
CREATE OR REPLACE FUNCTION provision_domain_renew_job() RETURNS TRIGGER AS $$
DECLARE
    v_renew        RECORD;
    _parent_job_id UUID;
BEGIN
    WITH price AS (
        SELECT
            CASE
                WHEN voip.price IS NULL THEN NULL
                ELSE JSONB_BUILD_OBJECT(
                    'amount', voip.price,
                    'currency', voip.currency_type_code,
                    'fraction', voip.currency_type_fraction
                )
            END AS data
        FROM v_order_item_price voip
                 JOIN v_order_renew_domain vord ON voip.order_item_id = vord.order_item_id AND voip.order_id = vord.order_id
        WHERE vord.domain_name = NEW.domain_name
        ORDER BY vord.created_date DESC
        LIMIT 1
    )
    SELECT
        NEW.id AS provision_domain_renew_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pr.domain_name AS domain_name,
        pr.current_expiry_date AS expiry_date,
        pr.period AS period,
        price.data AS price,
        pr.order_metadata AS metadata
    INTO v_renew
    FROM provision_domain_renew pr
            LEFT JOIN price ON TRUE
            JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
            JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pr.id = NEW.id;

    SELECT job_create(
            v_renew.tenant_customer_id,
            'provision_domain_renew',
            NEW.id,
            TO_JSONB(v_renew.*) - 'period' - 'expiry_date' -- Job data should not include current expiry date and period as it might change.
        ) INTO _parent_job_id;
    
    UPDATE provision_domain_renew SET job_id = _parent_job_id WHERE id=NEW.id;

    PERFORM job_submit(
            v_renew.tenant_customer_id,
            'setup_domain_renew',
            NEW.id,
            TO_JSONB(v_renew.*),
            _parent_job_id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
