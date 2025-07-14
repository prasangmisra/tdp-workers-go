--
-- table: order_item_delete_domain
-- description: this table stores attributes of domain related orders.
--

CREATE TABLE order_item_delete_domain (
  domain_id             UUID NOT NULL,
  name                  FQDN NOT NULL,
  accreditation_tld_id  UUID NOT NULL REFERENCES accreditation_tld,
  hosts                 TEXT[], -- for backward compatibility, to be removed in next iteration (See ticket TDP-5008)
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain delete is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('delete');

-- check if domain from order data exists
CREATE TRIGGER a_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_delete_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();

-- force initial status
CREATE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_delete_domain
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- sets the TLD_ID on when the it does not contain one
CREATE TRIGGER order_item_set_tld_id_tg 
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW WHEN ( NEW.accreditation_tld_id IS NULL)
    EXECUTE PROCEDURE order_item_set_tld_id();

-- prevents order creation if domain delete locked
CREATE TRIGGER order_prevent_if_domain_delete_prohibited_tg
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_operation_prohibited('delete');

-- check if the domain on the order data is deleted
CREATE TRIGGER order_prevent_if_domain_is_deleted_tg
    BEFORE INSERT ON order_item_delete_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_is_deleted();

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_delete_plan_tg
    AFTER UPDATE ON order_item_delete_domain
    FOR EACH ROW WHEN ( 
      OLD.status_id <> NEW.status_id 
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    )EXECUTE PROCEDURE plan_order_item();

-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_delete_domain
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_delete_domain
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_delete_domain(order_id);
CREATE INDEX ON order_item_delete_domain(status_id);


-- this table contains the plan for deleting a domain
CREATE TABLE delete_domain_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_delete_domain
) INHERITS(order_item_plan,class.audit_trail);

CREATE TRIGGER plan_delete_domain_provision_domain_tg
  AFTER UPDATE ON delete_domain_plan
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain') 
  )
  EXECUTE PROCEDURE plan_delete_domain_provision();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON delete_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
