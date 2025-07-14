DROP TRIGGER IF EXISTS order_item_plan_update_tg ON create_contact_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON create_contact_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_contact_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON create_contact_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON create_contact_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON create_domain_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON create_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON create_domain_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON create_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON create_host_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON create_host_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_host_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON create_host_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON create_host_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON create_hosting_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON create_hosting_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_hosting_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON create_hosting_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON create_hosting_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON delete_contact_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON delete_contact_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_contact_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON delete_contact_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON delete_contact_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON delete_domain_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON delete_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON delete_domain_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON delete_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON redeem_domain_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON redeem_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON redeem_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON redeem_domain_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON redeem_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON renew_domain_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON renew_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON renew_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON renew_domain_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON renew_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON transfer_in_domain_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON transfer_in_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON transfer_in_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON transfer_in_domain_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON transfer_in_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON update_contact_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON update_contact_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_contact_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON update_contact_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON update_contact_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON update_domain_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON update_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON update_domain_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();  

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON update_host_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON update_host_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_host_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON update_host_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON update_host_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON update_hosting_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON update_hosting_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_hosting_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON update_hosting_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON update_hosting_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON delete_hosting_plan;
DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON delete_hosting_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_hosting_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_processed_tg ON delete_hosting_plan;
CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON delete_hosting_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();

DROP FUNCTION order_item_plan_update;