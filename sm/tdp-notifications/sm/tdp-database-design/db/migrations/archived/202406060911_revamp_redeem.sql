INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES(
    'is_redeem_report_required',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry requires redemption report for redemption commands',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
) ON CONFLICT DO NOTHING;

INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key
) values
(
    'provision_domain_redeem_report',
    'Sends domain redeem report',
    'provision_domain_redeem',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
) ON CONFLICT DO NOTHING;

ALTER TABLE provision_domain_redeem
    DROP COLUMN IF EXISTS is_request,
    DROP COLUMN IF EXISTS is_report;

-- function: provision_domain_redeem_job()
-- description: creates the job to redeem the domain
CREATE OR REPLACE FUNCTION provision_domain_redeem_job() RETURNS TRIGGER AS $$
DECLARE
  v_redeem                      RECORD;
  v_domain                      RECORD;
  _parent_job_id                UUID;
  _is_redeem_report_required    BOOLEAN;
BEGIN
    WITH contacts AS (
        SELECT JSON_AGG(
                    JSONB_BUILD_OBJECT(
                            'type', dct.name,
                            'handle',dc.handle
                    )
            ) AS data
        FROM provision_domain_redeem pdr
        JOIN domain d ON d.id = pdr.domain_id
        JOIN domain_contact dc on dc.domain_id = d.id
        JOIN domain_contact_type dct ON dct.id = dc.domain_contact_type_id
        WHERE pdr.id = NEW.id
    ),
        hosts AS (
            SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                                'name',
                                h.name
                        )
                ) AS data
            FROM provision_domain_redeem pdr
            JOIN domain d ON d.id = pdr.domain_id
            JOIN domain_host dh ON dh.domain_id = d.id
            JOIN host h ON h.id = dh.host_id
            WHERE pdr.id = NEW.id
        )
    SELECT
    d.name AS domain_name,
    'ok' AS status,
    d.deleted_date AS delete_date,
    NOW() AS restore_date,
    d.ry_expiry_date AS expiry_date,
    d.ry_created_date AS create_date,
    contacts.data AS contacts,
    hosts.data AS nameservers,
    TO_JSONB(a.*) AS accreditation,
    tnc.id AS tenant_customer_id,
    NEW.id AS provision_domain_redeem_id,
    pr.order_metadata AS metadata
    INTO v_redeem
    FROM provision_domain_redeem pr
    JOIN contacts ON TRUE
    JOIN hosts ON TRUE
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    JOIN domain d ON d.id=pr.domain_id
    WHERE pr.id = NEW.id;

    SELECT * INTO v_domain
    FROM domain d
    WHERE d.id=NEW.domain_id
    AND d.tenant_customer_id=NEW.tenant_customer_id;

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.is_redeem_report_required',
        p_tld_id=>vat.tld_id,
        p_tenant_id=>vtc.tenant_id
    ) INTO _is_redeem_report_required
    FROM v_accreditation_tld vat
    JOIN v_tenant_customer vtc ON vtc.id = v_domain.tenant_customer_id
    WHERE vat.accreditation_tld_id = v_domain.accreditation_tld_id;

    IF _is_redeem_report_required THEN
        SELECT job_create(
            v_redeem.tenant_customer_id,
            'provision_domain_redeem_report',
            NEW.id,
            TO_JSONB(v_redeem.*)
        ) INTO _parent_job_id;

        UPDATE provision_domain_redeem SET job_id = _parent_job_id WHERE id=NEW.id;

        PERFORM job_submit(
            v_redeem.tenant_customer_id,
            'provision_domain_redeem',
            NULL,
            TO_JSONB(v_redeem.*),
            _parent_job_id
        );
    ELSE
        UPDATE provision_domain_redeem SET job_id=job_submit(
            v_redeem.tenant_customer_id,
            'provision_domain_redeem',
            NEW.id,
            TO_JSONB(v_redeem.*)
        ) WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- updates the parent job with the status value
-- according to child jobs and flags.
--

CREATE OR REPLACE FUNCTION job_parent_status_update() RETURNS TRIGGER AS $$
DECLARE
    _job_status            RECORD;
    _parent_job            RECORD;
BEGIN

    -- no parent; nothing to do
    IF NEW.parent_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT * INTO _job_status FROM job_status WHERE id = NEW.status_id;

    -- child job not final; nothing to do
    IF NOT _job_status.is_final THEN
        RETURN NEW;
    END IF;

    -- parent has final status; nothing to do
    SELECT * INTO _parent_job FROM v_job WHERE job_id = NEW.parent_id;
    IF _parent_job.job_status_is_final THEN
        RETURN NEW;
    END IF;

    -- child job failed hard; fail parent
    IF NOT _job_status.is_success AND NEW.is_hard_fail THEN
        UPDATE job
        SET
            status_id = tc_id_from_name('job_status', 'failed'),
            result_message = NEW.result_message
        WHERE id = NEW.parent_id;
        RETURN NEW;
    END IF;

    -- check for unfinished children jobs
    PERFORM TRUE FROM v_job WHERE job_parent_id = NEW.parent_id AND NOT job_status_is_final;

    IF NOT FOUND THEN

        PERFORM TRUE FROM v_job WHERE job_parent_id = NEW.parent_id AND job_status_is_success;

        IF FOUND THEN
            UPDATE job SET status_id = tc_id_from_name('job_status', 'submitted') WHERE id = NEW.parent_id;
        ELSE
            -- all children jobs had failed
            UPDATE job
            SET
                status_id = tc_id_from_name('job_status', 'failed'),
                result_message = NEW.result_message
            WHERE id = NEW.parent_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;