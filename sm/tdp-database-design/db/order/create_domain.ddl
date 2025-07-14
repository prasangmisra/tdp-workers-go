--
-- table: order_item_create_domain
-- description: this table stores attributes of domain related orders.
--

CREATE TABLE order_item_create_domain (
  name                  FQDN NOT NULL,
  registration_period   INT NOT NULL DEFAULT 1,
  accreditation_tld_id  UUID NOT NULL REFERENCES accreditation_tld,
  auto_renew            BOOLEAN NOT NULL DEFAULT TRUE,
  locks                 JSONB,
  launch_data           JSONB,
  auth_info             TEXT,
  secdns_max_sig_life   INT,
  tags                  TEXT[],
  metadata              JSONB DEFAULT '{}'::JSONB,
  uname                 TEXT,
  language              TEXT,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain create is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('registration');

-- prevent order creation if domain syntax is invalid
CREATE TRIGGER validate_domain_syntax_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_syntax();

-- prevent order crearion if registration period is invalid
CREATE TRIGGER validate_period_tg
    BEFORE INSERT OR UPDATE ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_period('registration');

-- prevent order creation if auth_info is invalid
CREATE TRIGGER validate_auth_info_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_auth_info('registration');

CREATE TRIGGER order_item_force_initial_status_tg
    BEFORE INSERT ON order_item_create_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- sets the TLD_ID on when the item does not contain one
CREATE TRIGGER order_item_set_tld_id_tg 
    BEFORE INSERT ON order_item_create_domain 
    FOR EACH ROW WHEN (NEW.accreditation_tld_id IS NULL)
    EXECUTE PROCEDURE order_item_set_tld_id();

-- sets the IDN Uname when the item does not contain one
CREATE TRIGGER order_item_set_idn_uname_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW WHEN (
      NEW.uname IS NULL
      AND NEW.language IS NOT NULL
    )
    EXECUTE PROCEDURE order_item_set_idn_uname();

-- prevents order creation for already existing domain
CREATE TRIGGER order_prevent_if_domain_exists_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_exists();

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_create_plan_tg
    AFTER UPDATE ON order_item_create_domain 
    FOR EACH ROW WHEN ( 
      OLD.status_id <> NEW.status_id 
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    )EXECUTE PROCEDURE plan_order_item();


-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_create_domain 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_create_domain
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_create_domain(order_id);
CREATE INDEX ON order_item_create_domain(status_id);


-- 
-- table: create_domain_contact
-- description: contacts associated with the domain create order
--
CREATE TABLE create_domain_contact(
      id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
      create_domain_id        UUID NOT NULL REFERENCES order_item_create_domain,
      domain_contact_type_id  UUID NOT NULL REFERENCES domain_contact_type,
      order_contact_id        UUID,
      short_id                TEXT,
      UNIQUE(create_domain_id,domain_contact_type_id,order_contact_id)
) INHERITS(class.audit);

CREATE INDEX ON create_domain_contact(create_domain_id);
CREATE INDEX ON create_domain_contact(domain_contact_type_id);
CREATE INDEX ON create_domain_contact(order_contact_id);

COMMENT ON TABLE create_domain_contact IS 
'contains the association of contacts and domains at order time';

COMMENT ON COLUMN create_domain_contact.order_contact_id IS 
'since the order_contact table inherits from the contact table, the 
data will be available in the contact, this also allow for contact
reutilization';

CREATE OR REPLACE TRIGGER a_set_order_contact_id_from_short_id_tg
    BEFORE INSERT ON create_domain_contact
    FOR EACH ROW WHEN (
        NEW.order_contact_id IS NULL AND
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE set_order_contact_id_from_short_id();

CREATE TRIGGER order_prevent_if_create_domain_contact_does_not_exist_tg
    BEFORE INSERT ON create_domain_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
    EXECUTE PROCEDURE order_prevent_if_create_domain_contact_does_not_exist();

--
-- table: create_domain_nameserver
-- description: this table stores attributes of host related orders.
--

CREATE TABLE create_domain_nameserver (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  create_domain_id   UUID NOT NULL REFERENCES order_item_create_domain,
  host_id            UUID NOT NULL REFERENCES order_host  
) INHERITS(class.audit);

CREATE TABLE order_secdns_key_data(
  PRIMARY KEY(id)
) INHERITS(secdns_key_data);

CREATE TABLE order_secdns_ds_data(
  PRIMARY KEY(id),
  FOREIGN KEY (key_data_id) REFERENCES order_secdns_key_data
) INHERITS(secdns_ds_data);

CREATE TABLE create_domain_secdns (
  id                        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  create_domain_id          UUID NOT NULL REFERENCES order_item_create_domain,
  ds_data_id                UUID REFERENCES order_secdns_ds_data,
  key_data_id               UUID REFERENCES order_secdns_key_data,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  )
) INHERITS(class.audit);

CREATE INDEX create_domain_secdns_domain_id_idx ON create_domain_secdns(create_domain_id);

-- add trigger to ensure we stick to the same record type
CREATE TRIGGER create_domain_secdns_check_single_record_type_tg
  BEFORE INSERT ON create_domain_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_secdns_type('create_domain_secdns', 'create_domain_id');

-- add trigger to validate the domain secdns data
CREATE TRIGGER validate_domain_secdns_data_tg
  BEFORE INSERT ON create_domain_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_domain_secdns_data();

CREATE INDEX ON create_domain_nameserver(create_domain_id);
CREATE INDEX ON create_domain_nameserver(host_id);

-- this table contains the plan for creating a domain
CREATE TABLE create_domain_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_create_domain
) INHERITS(order_item_plan,class.audit_trail);

CREATE TRIGGER validate_create_domain_plan_tg
    AFTER UPDATE ON create_domain_plan
    FOR EACH ROW WHEN (
      OLD.validation_status_id <> NEW.validation_status_id
      AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
    )
    EXECUTE PROCEDURE validate_create_domain_plan();

CREATE TRIGGER validate_create_domain_host_plan_tg
    AFTER UPDATE ON create_domain_plan
    FOR EACH ROW WHEN (
      OLD.validation_status_id <> NEW.validation_status_id
      AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host')
    )
    EXECUTE PROCEDURE validate_create_domain_host_plan();

CREATE TRIGGER plan_create_domain_provision_host_tg 
  AFTER UPDATE ON create_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host') 
  )
  EXECUTE PROCEDURE plan_create_domain_provision_host();

CREATE TRIGGER plan_create_domain_provision_contact_tg 
  AFTER UPDATE ON create_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','contact') 
  )
  EXECUTE PROCEDURE plan_create_domain_provision_contact();

CREATE TRIGGER plan_create_domain_provision_domain_tg 
  AFTER UPDATE ON create_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain') 
  )
  EXECUTE PROCEDURE plan_create_domain_provision_domain();

-- host already provisioned just insert records accordingly
CREATE TRIGGER plan_create_domain_provision_host_skipped_tg 
  AFTER UPDATE ON create_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id = tc_id_from_name('order_item_plan_status','new')
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','completed')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host') 
  )
  EXECUTE PROCEDURE provision_domain_host_skipped();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON create_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
  