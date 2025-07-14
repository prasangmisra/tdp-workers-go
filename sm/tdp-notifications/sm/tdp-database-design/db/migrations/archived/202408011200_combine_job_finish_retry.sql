DROP TRIGGER IF EXISTS job_retry_tg ON job;
DROP TRIGGER IF EXISTS job_finish_tg ON job;

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

DROP FUNCTION IF EXISTS job_retry();

CREATE TRIGGER job_finish_tg BEFORE UPDATE ON job 
       FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id)
       EXECUTE PROCEDURE job_finish();