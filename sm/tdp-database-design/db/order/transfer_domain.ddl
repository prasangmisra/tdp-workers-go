

--
-- table: transfer_status
-- description: this table lists the possible transfer statuses.
--

CREATE TABLE transfer_status (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  descr      TEXT NOT NULL,
  is_final   BOOLEAN NOT NULL,
  is_success BOOLEAN NOT NULL,
  UNIQUE (name)
);

--
-- table: order_item_transfer_in_domain
-- description: this table stores attributes of domain transfer orders.
--

CREATE TABLE order_item_transfer_in_domain (
  name                  FQDN NOT NULL,
  accreditation_tld_id  UUID NOT NULL REFERENCES accreditation_tld,
  transfer_period       INT NOT NULL DEFAULT 1,
  auth_info             TEXT,
  tags                  TEXT[],
  metadata              JSONB DEFAULT '{}'::JSONB,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_transfer_in_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain transfer is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_transfer_in_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('transfer_in');

-- prevent order creation if domain syntax is invalid
CREATE TRIGGER validate_domain_syntax_tg
    BEFORE INSERT ON order_item_transfer_in_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_syntax();

-- make sure the initial status is 'pending'
CREATE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- sets the TLD_ID on when the it does not contain one
CREATE TRIGGER order_item_set_tld_id_tg 
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW WHEN ( NEW.accreditation_tld_id IS NULL )
  EXECUTE PROCEDURE order_item_set_tld_id();

-- make sure the transfer period is valid
CREATE TRIGGER validate_period_tg
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW EXECUTE PROCEDURE validate_period('transfer_in');

-- make sure the transfer auth info is valid
CREATE TRIGGER validate_auth_info_tg
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW EXECUTE PROCEDURE validate_auth_info('transfer_in');

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_create_plan_tg
  AFTER UPDATE ON order_item_transfer_in_domain 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE plan_order_item();

-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_transfer_in_domain 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_transfer_in_domain
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_transfer_in_domain(order_id);
CREATE INDEX ON order_item_transfer_in_domain(status_id);

-- this table contains the plan for transfering a domain
CREATE TABLE transfer_in_domain_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_transfer_in_domain
) INHERITS(order_item_plan,class.audit_trail);

CREATE TRIGGER validate_transfer_domain_plan_tg
    AFTER UPDATE ON transfer_in_domain_plan
    FOR EACH ROW WHEN (
      OLD.validation_status_id <> NEW.validation_status_id
      AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
      AND NEW.provision_order = 1
    )
    EXECUTE PROCEDURE validate_transfer_domain_plan();

CREATE TRIGGER plan_transfer_in_domain_provision_domain_tg 
  AFTER UPDATE ON transfer_in_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain') 
  )
  EXECUTE PROCEDURE plan_transfer_in_domain_provision_domain();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON transfer_in_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON transfer_in_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
