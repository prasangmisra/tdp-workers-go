--
-- table: order_item_create_hosting_client
-- description: this table stores client information associated with order_item_create_hosting
--
CREATE TABLE order_item_create_hosting_client (
    PRIMARY KEY (id)
) INHERITS (hosting_client);

--
-- table: order_hosting_certificate
-- description: this table stores certificate information associated with order_item_create_hosting
--
CREATE TABLE order_hosting_certificate (
    PRIMARY KEY (id)
) INHERITS (hosting_certificate);

--
-- table: order_item_create_hosting
-- description: this table stored attributes of hosting related orders
--
CREATE TABLE order_item_create_hosting (
    PRIMARY KEY (id),
    FOREIGN KEY (client_id) REFERENCES order_item_create_hosting_client,
    FOREIGN KEY (certificate_id) REFERENCES order_hosting_certificate,
    FOREIGN KEY (order_id) REFERENCES "order",
    FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item, hosting, class.audit_trail);

CREATE TRIGGER order_item_check_hosting_domain_exists_tg
    BEFORE INSERT ON order_item_create_hosting
    FOR EACH ROW EXECUTE PROCEDURE order_item_check_hosting_domain_exists();

CREATE TRIGGER order_item_force_initial_status_tg
    BEFORE INSERT ON order_item_create_hosting
    FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

CREATE TRIGGER order_item_check_active_orders_tg
    BEFORE INSERT ON order_item_create_hosting
    FOR EACH ROW EXECUTE PROCEDURE enforce_single_active_hosting_order_by_name();

-- more award to do this as a before trigger but it should happen before the plan is created
CREATE TRIGGER order_item_create_hosting_record_tg
    AFTER INSERT ON order_item_create_hosting
    FOR EACH ROW EXECUTE PROCEDURE order_item_create_hosting_record();    

-- Creates an execution plan for the order item
CREATE TRIGGER a_order_item_create_plan_tg
    AFTER UPDATE ON order_item_create_hosting
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id AND
        NEW.status_id = tc_id_from_name('order_item_status', 'ready')
    ) EXECUTE PROCEDURE plan_simple_order_item();

-- Start the execution of the order
CREATE TRIGGER b_order_item_plan_start_tg
    AFTER UPDATE ON order_item_create_hosting
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id AND
        NEW.status_id = tc_id_from_name('order_item_status', 'ready')
    ) EXECUTE PROCEDURE order_item_plan_start();

-- When the order item completes
CREATE TRIGGER  order_item_finish_tg
    AFTER UPDATE ON order_item_create_hosting
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id
    ) EXECUTE PROCEDURE order_item_finish();

CREATE INDEX ON order_item_create_hosting(order_id);
CREATE INDEX ON order_item_create_hosting(status_id);
CREATE INDEX ON order_item_create_hosting USING GIN(tags);


-- create hosting order planning
CREATE TABLE create_hosting_plan(
    PRIMARY KEY(id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_create_hosting
) INHERITS(order_item_plan, class.audit_trail);

CREATE TRIGGER plan_create_hosting_certificate_provision_tg
    AFTER UPDATE ON create_hosting_plan
    FOR EACH ROW WHEN (
            OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status', 'processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','hosting_certificate')
    )
EXECUTE  PROCEDURE plan_create_hosting_certificate_provision();

CREATE TRIGGER plan_create_hosting_provision_hosting_tg
    AFTER UPDATE ON create_hosting_plan
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','hosting')
    )
    EXECUTE PROCEDURE plan_create_hosting_provision();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_hosting_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON create_hosting_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
