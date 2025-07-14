DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON transfer_away_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON transfer_away_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();
