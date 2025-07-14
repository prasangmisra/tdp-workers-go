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
