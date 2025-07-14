--
-- table: update_internal_domain_plan
-- description: this table contains the plan for updating domain internally
--
CREATE TABLE update_internal_domain_plan(
  PRIMARY KEY(id)
) INHERITS(order_item_plan, class.audit_trail);

CREATE TRIGGER plan_update_internal_domain_tg 
  AFTER UPDATE ON update_internal_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE plan_update_internal_domain();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_internal_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON update_internal_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
