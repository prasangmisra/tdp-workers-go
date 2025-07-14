--
-- table: order_item_update_host
-- description: this table stores attributes of host related orders.
--

CREATE TABLE order_item_update_host (
  host_id UUID NOT NULL,
  new_host_id UUID NOT NULL REFERENCES order_host,
  host_name FQDN NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status 
) INHERITS (order_item,class.audit_trail);

-- prevents order creation for non-existing host
CREATE TRIGGER a_order_prevent_if_host_does_not_exist_tg
  BEFORE INSERT ON order_item_update_host
  FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_host_does_not_exist();

-- make sure the initial status is 'pending'
CREATE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_update_host
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_update_plan_tg
    AFTER UPDATE ON order_item_update_host
    FOR EACH ROW WHEN ( 
      OLD.status_id <> NEW.status_id 
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    ) EXECUTE PROCEDURE plan_simple_order_item();

-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_update_host
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER order_item_finish_tg
  AFTER UPDATE ON order_item_update_host
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_update_host(order_id);
CREATE INDEX ON order_item_update_host(status_id);

-- this table contains the plan for updating a host
CREATE TABLE update_host_plan(
    PRIMARY KEY(id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_update_host
) INHERITS (order_item_plan,class.audit_trail);

-- starts the execution of the update host plan
CREATE TRIGGER plan_update_host_provision_host_tg
  AFTER UPDATE ON update_host_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
  ) EXECUTE PROCEDURE plan_update_host_provision();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_host_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON update_host_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
