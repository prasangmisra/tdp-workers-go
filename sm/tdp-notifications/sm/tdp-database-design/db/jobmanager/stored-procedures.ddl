--
-- updates the referenced table with the referenced status values
-- ensuring that this matches the job result.  
--

CREATE OR REPLACE FUNCTION job_reference_status_update() RETURNS TRIGGER AS $$
DECLARE
  _job_type               RECORD;
  _job_status             RECORD;
  _target_status          RECORD;
BEGIN
  SELECT * INTO _job_type FROM job_type WHERE id = NEW.type_id;

  IF _job_type.reference_table IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO _job_status FROM job_status WHERE id = NEW.status_id;

  IF NOT _job_status.is_final THEN
    RETURN NEW;
  END IF;

  -- First check if there are reference specific overrides
  EXECUTE FORMAT(
    'SELECT rst.* FROM %s rst JOIN job_reference_status_override jrso ON jrso.reference_status_id = rst.id WHERE jrso.status_id = $1',
    _job_type.reference_status_table
  )
    INTO _target_status
    USING _job_status.id;

  IF _target_status.id IS NULL THEN
    EXECUTE FORMAT('SELECT * FROM %s WHERE is_final AND is_success = $1',_job_type.reference_status_table)
      INTO _target_status
      USING _job_status.is_success;

    IF _target_status.id IS NULL THEN
      RAISE EXCEPTION 'no target status found in table % where is_success=%',
        _job_type.reference_status_table,_job_status.is_success;
    END IF;
  END IF;

  EXECUTE FORMAT('UPDATE "%s" SET %s = $1 WHERE id = $2',
    _job_type.reference_table,
    _job_type.reference_status_column
  )
  USING _target_status.id,NEW.reference_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


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


--
-- job_create is used to create a job.
--

CREATE OR REPLACE FUNCTION job_create(
  _tenant_customer_id   UUID,
  _job_type             TEXT,
  _reference_id         UUID,
  _data                 JSONB DEFAULT '{}'::JSONB,
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
    data,
    parent_id,
    is_hard_fail
  ) VALUES($1,$2,$3,$4,$5,$6) RETURNING id'
  INTO
    _new_job_id
  USING
    _tenant_customer_id,
    tc_id_from_name('job_type',_job_type),
    _reference_id,
    _data,
    _job_parent_id,
    _is_hard_fail;

  RETURN _new_job_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION job_create IS
'creates a new job given a tenant_customer_id 
UUID,job_type TEXT,reference_id UUID';


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

COMMENT ON FUNCTION job_submit IS
'submits a new job which given a tenant_customer_id 
UUID,job_type TEXT,reference_id UUID';

--
-- job_submit_retriable is used to create a job and submit it right away.
--

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


--
-- job_complete_noop completes the job which is of is_noop type.
--

CREATE OR REPLACE FUNCTION job_complete_noop() RETURNS TRIGGER AS
$$
DECLARE 
  v_job_type RECORD;
BEGIN

  SELECT * INTO v_job_type FROM job_type WHERE id=NEW.type_id;

  IF v_job_type.is_noop THEN 
    NEW.status_id = tc_id_from_name('job_status','completed');
  END IF;

  RETURN NEW;
END;
$$
LANGUAGE plpgsql;


--
-- job_event_notify is used to notify an event when a job is created.
--

CREATE OR REPLACE FUNCTION job_event_notify() RETURNS TRIGGER AS
$$
DECLARE
    _payload JSONB;
BEGIN

  SELECT
    JSONB_BUILD_OBJECT(
      'job_id',j.job_id,
      'type',j.job_type_name,
      'status',j.job_status_name,
      'reference_id',j.reference_id,
      'reference_table',j.reference_table,
      'routing_key',j.routing_key,
      'metadata',
      CASE WHEN j.data ? 'metadata' 
      THEN
      (j.data -> 'metadata')
      ELSE
      '{}'::JSONB
      END
    )
  INTO _payload
  FROM v_job j
  WHERE job_id = NEW.id;
  
  PERFORM notify_event('job_event','job_event_notify',_payload::TEXT);

  RETURN NEW;
END;
$$
LANGUAGE plpgsql;


--
-- job_finish is used to finish a job.
--

CREATE OR REPLACE FUNCTION job_finish() RETURNS TRIGGER AS
$$
DECLARE 
  v_job_status RECORD;
BEGIN

 -- first check if job should be retried
 -- if not then see if we should set enddate


  SELECT * INTO v_job_status FROM job_status WHERE id=NEW.status_id;

  IF NOT v_job_status.is_final THEN
    RETURN NEW;
  END IF;

  IF v_job_status.id = tc_id_from_name('job_status','failed') THEN
    NEW.retry_count = NEW.retry_count + 1;
    IF NEW.retry_count < NEW.max_retries THEN
      NEW.status_id = tc_id_from_name('job_status','submitted');
      NEW.start_date = NOW() + NEW.retry_interval;

      -- exit early, so we don't set end_date
      RETURN NEW;
    END IF;
  END IF;

  NEW.end_date = NOW();

  RETURN NEW;
END;
$$
LANGUAGE plpgsql;


--
-- job_prevent_if_final prevents a job from being modified if it has a final status
--

CREATE OR REPLACE FUNCTION job_prevent_if_final() RETURNS TRIGGER AS
$$
DECLARE 
  v_job_status RECORD;
BEGIN

  SELECT * INTO v_job_status FROM job_status WHERE id=OLD.status_id;

  IF v_job_status.is_final THEN 
    RAISE EXCEPTION 'cannot modify job (%), has status: %',NEW.id,v_job_status.name;
  END IF;

  RETURN NEW;
END;
$$
LANGUAGE plpgsql;
