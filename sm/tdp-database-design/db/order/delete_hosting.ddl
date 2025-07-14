--
-- table: order_item_delete_hosting
-- description: this table stored attributes of hosting related orders
--
CREATE TABLE order_item_delete_hosting (
    hosting_id UUID NOT NULL REFERENCES hosting(id),
    PRIMARY KEY (id),
    FOREIGN KEY (order_id) REFERENCES "order",
    FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item, class.audit_trail);

CREATE TRIGGER order_item_check_hosting_deleted_tg
    BEFORE INSERT ON order_item_delete_hosting
    FOR EACH ROW EXECUTE PROCEDURE order_item_check_hosting_deleted();

CREATE TRIGGER order_item_force_initial_status_tg
    BEFORE INSERT ON order_item_delete_hosting
    FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

CREATE TRIGGER order_item_check_active_orders_tg
    BEFORE INSERT ON order_item_delete_hosting
    FOR EACH ROW EXECUTE PROCEDURE enforce_single_active_hosting_order_by_id();

-- Creates an execution plan for the order item
CREATE TRIGGER a_order_item_delete_plan_tg
    AFTER UPDATE ON order_item_delete_hosting
    FOR EACH ROW WHEN (
            OLD.status_id <> NEW.status_id AND
            NEW.status_id = tc_id_from_name('order_item_status', 'ready')
    ) EXECUTE PROCEDURE plan_simple_order_item();

-- Start the execution of the order
CREATE TRIGGER b_order_item_plan_start_tg
    AFTER UPDATE ON order_item_delete_hosting
    FOR EACH ROW WHEN (
            OLD.status_id <> NEW.status_id AND
            NEW.status_id = tc_id_from_name('order_item_status', 'ready')
    ) EXECUTE PROCEDURE order_item_plan_start();

-- When the order item completes
CREATE TRIGGER  order_item_finish_tg
    AFTER UPDATE ON order_item_delete_hosting
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id
    ) EXECUTE PROCEDURE order_item_finish();

CREATE INDEX ON order_item_delete_hosting(order_id);
CREATE INDEX ON order_item_delete_hosting(status_id);

-- delete hosting order planning
CREATE TABLE delete_hosting_plan(
    PRIMARY KEY(id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_delete_hosting
) INHERITS(order_item_plan, class.audit_trail);

CREATE TRIGGER plan_delete_hosting_provision_hosting_tg
    AFTER UPDATE ON delete_hosting_plan
    FOR EACH ROW WHEN (
            OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','hosting')
    )
    EXECUTE PROCEDURE plan_delete_hosting_provision();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_hosting_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON delete_hosting_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
