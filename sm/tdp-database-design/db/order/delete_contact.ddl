--
-- table: order_item_delete_contact
-- description: this table stores attributes of contact related orders.
--

CREATE TABLE order_item_delete_contact (
  contact_id UUID NOT NULL REFERENCES contact,
  short_id TEXT REFERENCES contact(short_id),
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

CREATE TRIGGER a_set_contact_id_from_short_id_tg
    BEFORE INSERT ON order_item_delete_contact
    FOR EACH ROW WHEN (
        NEW.contact_id IS NULL AND
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE set_contact_id_from_short_id();

CREATE TRIGGER b_order_prevent_contact_in_use_tg
    BEFORE INSERT ON order_item_delete_contact
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_contact_in_use();

-- make sure the initial status is 'pending'
CREATE TRIGGER order_item_force_initial_status_tg
    BEFORE INSERT ON order_item_delete_contact
    FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_create_plan_tg
    AFTER UPDATE ON order_item_delete_contact
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    )EXECUTE PROCEDURE plan_simple_order_item();

-- starts the execution of the order
CREATE TRIGGER b_order_item_plan_start_tg
    AFTER UPDATE ON order_item_delete_contact
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
    AFTER UPDATE ON order_item_delete_contact
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    ) EXECUTE PROCEDURE order_item_finish();

CREATE INDEX ON order_item_delete_contact(order_id);
CREATE INDEX ON order_item_delete_contact(status_id);

-- this table contains the plan for deleting a contact
CREATE TABLE delete_contact_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_delete_contact
) INHERITS(order_item_plan,class.audit_trail);

CREATE TRIGGER plan_delete_contact_provision_contact_tg
  AFTER UPDATE ON delete_contact_plan
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','contact')
  )
  EXECUTE PROCEDURE plan_delete_contact_provision();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_contact_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON delete_contact_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
