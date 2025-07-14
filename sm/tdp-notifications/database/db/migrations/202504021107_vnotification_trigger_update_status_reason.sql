--
-- Update the trigger on the v_notification view so that the status_reason column is updated
--


CREATE OR REPLACE FUNCTION notification_delivery_update() RETURNS TRIGGER AS $$
BEGIN

  UPDATE notification_delivery SET
    status_id = tc_id_from_name('notification_status', NEW.status),
    status_reason = NEW.status_reason
  WHERE
    id = NEW.id;

  RETURN NEW;
END
$$ LANGUAGE plpgsql;


