DROP VIEW IF EXISTS v_job;
DROP TRIGGER IF EXISTS job_retry_tg ON job;

-- modify job table to support retrying jobs

ALTER TABLE job DROP COLUMN IF EXISTS retry_date;

ALTER TABLE job ADD COLUMN IF NOT EXISTS retry_interval INTERVAL;
ALTER TABLE job ADD COLUMN IF NOT EXISTS max_retries INT DEFAULT 1;


-- recreate view without retry_date

CREATE OR REPLACE VIEW v_job AS
    SELECT 
        j.id AS job_id,
        j.parent_id AS job_parent_id,
        j.tenant_customer_id,
        js.name AS job_status_name,
        jt.name AS job_type_name,
        j.created_date,
        j.start_date,
        j.end_date,
        j.retry_count,
        j.reference_id,
        jt.reference_table,
        j.result_message AS result_message,
        j.result_data AS result_data,
        j.data AS data,
        TO_JSONB(vtc.*) AS tenant_customer,
        jt.routing_key,
        jt.is_noop AS job_type_is_noop,
        js.is_final AS job_status_is_final,
        js.is_success AS job_status_is_success,
        j.event_id,
        j.is_hard_fail
    FROM job j 
        JOIN job_status js ON j.status_id = js.id 
        JOIN job_type jt ON jt.id = j.type_id
        JOIN v_tenant_customer vtc ON vtc.id = j.tenant_customer_id
;

CREATE OR REPLACE FUNCTION job_submit_retriable(
  _tenant_customer_id   UUID,
  _job_type             TEXT,
  _reference_id         UUID,
  _data                 JSONB DEFAULT '{}'::JSONB,
  _start_date           TIMESTAMPTZ DEFAULT NOW(),
  _retry_interval       INTERVAL DEFAULT '1 minute',
  _max_retries          INT DEFAULT 1,
  _job_parent_id        UUID DEFAULT NULL,
  _is_hard_fail         BOOLEAN DEFAULT TRUE
) RETURNS UUID AS $$
DECLARE
  _new_job_id      UUID;
BEGIN
  
    EXECUTE 'INSERT INTO job(
      tenant_customer_id,
      type_id,
      reference_id,
      status_id,
      data,
      parent_id,
      is_hard_fail,
      retry_interval,
      max_retries,
      start_date
    ) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id'
    INTO
      _new_job_id
    USING
      _tenant_customer_id,
      tc_id_from_name('job_type',_job_type),
      _reference_id,
      tc_id_from_name('job_status', 'submitted'),
      _data,
      _job_parent_id,
      _is_hard_fail,
      _retry_interval,
      _max_retries,
      _start_date;
  
    RETURN _new_job_id;
  
  END;
$$ LANGUAGE plpgsql;


COMMENT ON FUNCTION job_submit_retriable IS
'submits a new retriable job';

-- needs to be created as a before update trigger on job
CREATE OR REPLACE FUNCTION job_retry() RETURNS TRIGGER AS
$$
  BEGIN
  -- steps:
  --        update retry_count (starts at 0, increments by 1)
  --        check if retry_count < max_retries
  --        update status to submitted 
  --        calculate new start date (now + retry_interval)

  NEW.retry_count = NEW.retry_count + 1;
  IF NEW.retry_count < NEW.max_retries THEN
    NEW.status_id = tc_id_from_name('job_status','submitted');
    NEW.start_date = NOW() + NEW.retry_interval;
  END IF;

  RETURN NEW;
  END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER job_retry_tg BEFORE UPDATE ON job
       FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id AND 
       NEW.status_id = tc_id_from_name('job_status','failed'))
       EXECUTE PROCEDURE job_retry();