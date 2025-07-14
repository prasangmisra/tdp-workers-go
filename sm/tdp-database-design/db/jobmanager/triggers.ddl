CREATE TRIGGER job_notify_tg AFTER INSERT ON job
       FOR EACH ROW WHEN (
              NEW.start_date <= NOW()
              AND NEW.status_id = tc_id_from_name('job_status','submitted') 
       )
       EXECUTE PROCEDURE job_event_notify();

CREATE TRIGGER job_complete_noop_tg BEFORE UPDATE ON job 
       FOR EACH ROW WHEN (
              OLD.status_id <> NEW.status_id
              AND NEW.status_id = tc_id_from_name('job_status','submitted')
       )
       EXECUTE PROCEDURE job_complete_noop();

CREATE TRIGGER job_notify_submitted_tg AFTER UPDATE ON job 
       FOR EACH ROW WHEN (
              OLD.status_id <> NEW.status_id
              AND NEW.start_date <= NOW()
              AND NEW.status_id = tc_id_from_name('job_status','submitted')
       )
       EXECUTE PROCEDURE job_event_notify();

CREATE TRIGGER job_reference_status_update_tg AFTER UPDATE ON job 
       FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id)
       EXECUTE PROCEDURE job_reference_status_update();

CREATE TRIGGER job_parent_status_update_tg AFTER UPDATE ON job 
       FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id)
       EXECUTE PROCEDURE job_parent_status_update();

CREATE TRIGGER job_finish_tg BEFORE UPDATE ON job 
       FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id)
       EXECUTE PROCEDURE job_finish();

CREATE TRIGGER job_prevent_if_final_tg BEFORE UPDATE ON job 
       FOR EACH ROW EXECUTE PROCEDURE job_prevent_if_final();
