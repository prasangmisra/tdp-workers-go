-- Add attempt_count and allowed_attempts columns to provision table
ALTER TABLE class.provision
ADD COLUMN IF NOT EXISTS attempt_count INT DEFAULT 1,
ADD COLUMN IF NOT EXISTS allowed_attempts INT DEFAULT 1;

-- Insert the provision_retry_backoff_factor attribute
INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null
) VALUES (
    'provision_retry_backoff_factor',
    tc_id_from_name('attr_category', 'general'),
    'Exponential backoff factor for retrying failed operations',
    tc_id_from_name('attr_value_type', 'INTEGER'),
    4::TEXT,
    FALSE
) ON CONFLICT DO NOTHING;


-- function: job_start_date
-- description: This function calculates the start date for a job based on the attempt count.
CREATE OR REPLACE FUNCTION job_start_date(attempt_count INT) RETURNS TIMESTAMPTZ AS $$
DECLARE
  _factor INT;
  _start_date TIMESTAMPTZ;
BEGIN
  -- Get the default factor for exponential backoff
  SELECT default_value INTO _factor FROM attr_key WHERE name = 'provision_retry_backoff_factor';

  -- Calculate the start date for the job based on the attempt count (exponential backoff).
  _start_date := CASE
    WHEN attempt_count = 1 THEN NOW()
    ELSE NOW() + INTERVAL '1 second' * (_factor ^ (attempt_count - 1))
  END;

  RETURN _start_date;
END;
$$ LANGUAGE plpgsql;


-- Drop the old job_submit function and create a new one
DROP FUNCTION IF EXISTS job_submit;

--
-- job_submit is used to create a job and submit it right away.
--

CREATE OR REPLACE FUNCTION job_submit(
  _tenant_customer_id   UUID,
  _job_type             TEXT,
  _reference_id         UUID,
  _data                 JSONB DEFAULT '{}'::JSONB,
  _job_parent_id        UUID DEFAULT NULL,
  _start_date           TIMESTAMPTZ DEFAULT NOW(),
  _is_hard_fail         BOOLEAN DEFAULT TRUE
) RETURNS UUID AS $$
DECLARE
  _new_job_id      UUID;
BEGIN
  EXECUTE 'INSERT INTO job(
    tenant_customer_id,
    type_id,
    status_id,
    reference_id,
    data,
    parent_id,
    is_hard_fail,
    start_date
  ) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id'
  INTO
    _new_job_id
  USING
    _tenant_customer_id,
    tc_id_from_name('job_type',_job_type),
    tc_id_from_name('job_status', 'submitted'),
    _reference_id,
    _data,
    _job_parent_id,
    _is_hard_fail,
    _start_date;

  RETURN _new_job_id;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_renew_job()
-- description: creates the job to renew the domain
CREATE OR REPLACE FUNCTION provision_domain_renew_job() RETURNS TRIGGER AS $$
DECLARE
    v_renew        RECORD;
    _start_date    TIMESTAMPTZ;
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

    _start_date := job_start_date(NEW.attempt_count);

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
            _parent_job_id,
            _start_date
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_contact_update_job()
-- description: creates contact update parent and child jobs
CREATE OR REPLACE FUNCTION provision_contact_update_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id      UUID;
    _child_job          RECORD;
    v_contact           RECORD;
BEGIN
    SELECT job_create(
                   NEW.tenant_customer_id,
                   'provision_contact_update',
                   NEW.id,
                   to_jsonb(NULL::jsonb)
           ) INTO _parent_job_id;

    UPDATE provision_contact_update SET job_id= _parent_job_id
    WHERE id = NEW.id;

    FOR _child_job IN
        SELECT pdcu.*
        FROM provision_domain_contact_update pdcu
                 JOIN provision_status ps ON ps.id = pdcu.status_id
        WHERE pdcu.provision_contact_update_id = NEW.id AND
            ps.id = tc_id_from_name('provision_status','pending')
        LOOP
            SELECT
                _child_job.id AS provision_domain_contact_update_id,
                _child_job.tenant_customer_id AS tenant_customer_id,
                jsonb_get_order_contact_by_id(c.id) AS contact,
                TO_JSONB(a.*) AS accreditation,
                _child_job.handle AS handle
            INTO v_contact
            FROM ONLY order_contact c
                     JOIN v_accreditation a ON  a.accreditation_id = _child_job.accreditation_id
            WHERE c.id=_child_job.order_contact_id;

            UPDATE provision_domain_contact_update SET job_id=job_submit(
                    _child_job.tenant_customer_id,
                    'provision_domain_contact_update',
                    _child_job.id,
                    to_jsonb(v_contact.*),
                    _parent_job_id,
                    NOW(),
                    FALSE
                                                              ) WHERE id = _child_job.id;
        END LOOP;

    -- all child jobs are failed, fail the parent job
    IF NOT FOUND THEN
        UPDATE job
        SET status_id= tc_id_from_name('job_status', 'failed')
        WHERE id = _parent_job_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_contact_delete_job()
-- description: creates contact delete parent and child jobs
CREATE OR REPLACE FUNCTION provision_contact_delete_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id      UUID;
    _child_jobs         RECORD;
    v_contact           RECORD;
BEGIN
    SELECT job_create(
                   NEW.tenant_customer_id,
                   'provision_contact_delete_group',
                   NEW.id,
                   to_jsonb(NULL::jsonb)
           ) INTO _parent_job_id;

    UPDATE provision_contact_delete SET job_id= _parent_job_id WHERE id = NEW.id;

    FOR _child_jobs IN
        SELECT *
        FROM provision_contact_delete pcd
        WHERE pcd.parent_id = NEW.id
        LOOP
            SELECT
                TO_JSONB(a.*) AS accreditation,
                _child_jobs.handle AS handle,
                _child_jobs.order_metadata AS metadata
            INTO v_contact
            FROM v_accreditation a
            WHERE a.accreditation_id = _child_jobs.accreditation_id;

            UPDATE provision_contact_delete SET job_id=job_submit(
                    _child_jobs.tenant_customer_id,
                    'provision_contact_delete',
                    _child_jobs.id,
                    to_jsonb(v_contact.*),
                    _parent_job_id,
                    NOW(),
                    FALSE
                                                       ) WHERE id = _child_jobs.id;
        END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: keep_provision_status()
-- description: keep the status_id the same when called before update
CREATE OR REPLACE FUNCTION keep_provision_status_and_increment_attempt_count() RETURNS TRIGGER AS $$
BEGIN
    NEW.attempt_count := NEW.attempt_count + 1;
    NEW.status_id := OLD.status_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- keeps status the same when retrying is needed
CREATE OR REPLACE TRIGGER keep_provision_status_for_retry_tg
  BEFORE UPDATE ON provision_domain_renew
  FOR EACH ROW WHEN (
    OLD.attempt_count = NEW.attempt_count
    AND NEW.attempt_count < NEW.allowed_attempts
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE keep_provision_status_and_increment_attempt_count();


-- retries the domain renew order provision
CREATE OR REPLACE TRIGGER provision_domain_renew_retry_job_tg
  AFTER UPDATE ON provision_domain_renew
  FOR EACH ROW WHEN (
    OLD.attempt_count <> NEW.attempt_count
    AND NEW.attempt_count <= NEW.allowed_attempts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_renew_job();
