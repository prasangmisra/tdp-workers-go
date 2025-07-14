--
-- function: subscription_update()
-- description: called instead of update on v_subscription view
--

CREATE OR REPLACE FUNCTION subscription_update() RETURNS TRIGGER AS $$
BEGIN

  UPDATE subscription SET
    status_id = tc_id_from_name('subscription_status', NEW.status),
    notification_email = NEW.notification_email,
    descr = NEW.description,
    tags = NEW.tags,
    metadata = NEW.metadata,
    deleted_date = NEW.deleted_date
  WHERE
    id = NEW.id;

  RETURN NEW;
END
$$ LANGUAGE plpgsql;


-- Create the update trigger
CREATE TRIGGER subscription_update_tg
INSTEAD OF UPDATE ON v_subscription
FOR EACH ROW EXECUTE PROCEDURE subscription_update();
