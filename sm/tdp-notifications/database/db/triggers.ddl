CREATE TRIGGER subscription_force_initial_status_tg
  BEFORE INSERT ON subscription
  FOR EACH ROW EXECUTE PROCEDURE subscription_force_initial_status();

CREATE TRIGGER verify_poll_channel_tenant_specific_tg
  BEFORE INSERT ON subscription_poll_channel
  FOR EACH ROW EXECUTE PROCEDURE verify_poll_channel_tenant_specific();

CREATE TRIGGER set_subscription_channel_type_tg
  BEFORE INSERT ON subscription_poll_channel
  FOR EACH ROW EXECUTE PROCEDURE set_subscription_channel_type();

CREATE TRIGGER set_subscription_channel_type_tg
  BEFORE INSERT ON subscription_email_channel
  FOR EACH ROW EXECUTE PROCEDURE set_subscription_channel_type();

CREATE TRIGGER set_subscription_channel_type_tg
  BEFORE INSERT ON subscription_webhook_channel
  FOR EACH ROW EXECUTE PROCEDURE set_subscription_channel_type();

CREATE TRIGGER notfication_check_subscription_exists_tg
  BEFORE INSERT ON notification
  FOR EACH ROW EXECUTE PROCEDURE check_subscription_exists();

CREATE TRIGGER notification_create_deliveries_tg
  AFTER INSERT ON notification
  FOR EACH ROW EXECUTE PROCEDURE notification_create_deliveries();

CREATE TRIGGER notification_delivery_force_initial_status_tg
  BEFORE INSERT ON notification_delivery
  FOR EACH ROW EXECUTE PROCEDURE notification_delivery_force_initial_status();

CREATE TRIGGER subscription_update_tg
  INSTEAD OF UPDATE ON v_subscription
  FOR EACH ROW EXECUTE PROCEDURE subscription_update();

CREATE TRIGGER notification_delivery_update_tg 
  INSTEAD OF UPDATE ON v_notification
  FOR EACH ROW EXECUTE PROCEDURE notification_delivery_update();
