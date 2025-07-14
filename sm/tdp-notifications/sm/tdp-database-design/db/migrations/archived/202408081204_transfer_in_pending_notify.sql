ALTER TABLE IF EXISTS "order" ALTER COLUMN metadata SET DEFAULT '{}'::JSONB;

DROP TRIGGER IF EXISTS provision_domain_transfer_in_request_order_notify_tg ON provision_domain_transfer_in_request;
CREATE TRIGGER provision_domain_transfer_in_request_order_notify_tg
  AFTER UPDATE ON provision_domain_transfer_in_request
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();
