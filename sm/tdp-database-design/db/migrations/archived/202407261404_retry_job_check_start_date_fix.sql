DROP TRIGGER IF EXISTS job_notify_tg ON job;

CREATE TRIGGER job_notify_tg AFTER INSERT ON job
      FOR EACH ROW WHEN (
            NEW.start_date <= NOW()
            AND NEW.status_id = tc_id_from_name('job_status','submitted') 
      )
      EXECUTE PROCEDURE job_event_notify();

DROP TRIGGER IF EXISTS job_notify_submitted_tg ON job;

CREATE TRIGGER job_notify_submitted_tg AFTER UPDATE ON job 
      FOR EACH ROW WHEN (
            OLD.status_id <> NEW.status_id
            AND NEW.start_date <= NOW()
            AND NEW.status_id = tc_id_from_name('job_status','submitted')
      )
      EXECUTE PROCEDURE job_event_notify();
