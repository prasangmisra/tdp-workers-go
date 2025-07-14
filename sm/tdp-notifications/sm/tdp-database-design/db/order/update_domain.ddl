--
-- table: order_item_update_domain
-- description: this table stores attributes of domain related orders.
--

CREATE TABLE order_item_update_domain (
  domain_id             UUID NOT NULL,
  name                  FQDN NOT NULL,
  auth_info             TEXT,
  accreditation_tld_id  UUID NOT NULL REFERENCES accreditation_tld,
  auto_renew            BOOLEAN,
  locks                 JSONB,
  secdns_max_sig_life   INT,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain update is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('update');

-- prevent order creation if auth info is invalid
CREATE TRIGGER validate_auth_info_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_auth_info('update');

-- prevents order creation for non-existing domain
CREATE TRIGGER a_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();  

CREATE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_update_domain
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- sets the TLD_ID on when the it does not contain one
CREATE TRIGGER order_item_set_tld_id_tg 
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW WHEN ( NEW.accreditation_tld_id IS NULL)
    EXECUTE PROCEDURE order_item_set_tld_id();

-- prevents order creation id domain update locked
CREATE TRIGGER order_prevent_if_domain_update_prohibited_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_operation_prohibited('update');

-- check if the domain on the order data is deleted
CREATE TRIGGER order_prevent_if_domain_is_deleted_tg
    BEFORE INSERT ON order_item_update_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_is_deleted();

-- updates an execution plan for the item
CREATE TRIGGER a_order_item_update_plan_tg
    AFTER UPDATE ON order_item_update_domain
    FOR EACH ROW WHEN ( 
      OLD.status_id <> NEW.status_id 
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    ) EXECUTE PROCEDURE plan_order_item();

-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_update_domain
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_update_domain
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_update_domain(order_id);
CREATE INDEX ON order_item_update_domain(status_id);

-- 
-- table: update_domain_contact
-- description: contacts associated with the domain update order
--
CREATE TABLE update_domain_contact(
      id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
      update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
      domain_contact_type_id  UUID NOT NULL REFERENCES domain_contact_type,
      order_contact_id        UUID,
      short_id                TEXT,
      UNIQUE(update_domain_id,domain_contact_type_id,order_contact_id)
) INHERITS(class.audit);

CREATE INDEX ON update_domain_contact(update_domain_id);
CREATE INDEX ON update_domain_contact(domain_contact_type_id);
CREATE INDEX ON update_domain_contact(order_contact_id);

COMMENT ON TABLE update_domain_contact IS
'contains the association of contacts and domains at order time';

COMMENT ON COLUMN update_domain_contact.order_contact_id IS
'since the order_contact table inherits from the contact table, the 
data will be available in the contact, this also allow for contact
reutilization';

CREATE OR REPLACE TRIGGER a_set_order_contact_id_from_short_id_tg
    BEFORE INSERT ON update_domain_contact
    FOR EACH ROW WHEN (
        NEW.order_contact_id IS NULL AND
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE set_order_contact_id_from_short_id();

CREATE TRIGGER order_prevent_if_update_domain_contact_does_not_exist_tg
    BEFORE INSERT ON update_domain_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
    EXECUTE PROCEDURE order_prevent_if_update_domain_contact_does_not_exist();


--
-- table: update_domain_add_nameserver
-- description: this table stores attributes of host to be added to domain.
--

CREATE TABLE update_domain_add_nameserver (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  update_domain_id   UUID NOT NULL REFERENCES order_item_update_domain,
  host_id            UUID NOT NULL REFERENCES order_host  
) INHERITS(class.audit);

CREATE INDEX ON update_domain_add_nameserver(update_domain_id);
CREATE INDEX ON update_domain_add_nameserver(host_id);

--
-- table: update_domain_rem_nameserver
-- description: this table stores attributes of host to be removed from domain.
--

CREATE TABLE update_domain_rem_nameserver (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  update_domain_id   UUID NOT NULL REFERENCES order_item_update_domain,
  host_id            UUID NOT NULL REFERENCES order_host  
) INHERITS(class.audit);

CREATE INDEX ON update_domain_rem_nameserver(update_domain_id);
CREATE INDEX ON update_domain_rem_nameserver(host_id);


-- table: update_domain_add_contact
-- description: this table stores attributes of contact to be added to domain.
--
CREATE TABLE update_domain_add_contact (
    update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
    order_contact_id              UUID NOT NULL REFERENCES order_contact,
    domain_contact_type_id  UUID NOT NULL REFERENCES domain_contact_type,
    short_id                TEXT,
    PRIMARY KEY(update_domain_id,order_contact_id, domain_contact_type_id)
) INHERITS(class.audit);

CREATE TRIGGER order_prevent_if_update_domain_contact_does_not_exist_tg
    BEFORE INSERT ON update_domain_add_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_update_domain_contact_does_not_exist();


CREATE OR REPLACE TRIGGER a_set_order_contact_id_from_short_id_tg
    BEFORE INSERT ON update_domain_add_contact
    FOR EACH ROW WHEN (
    NEW.order_contact_id IS NULL AND
    NEW.short_id IS NOT NULL
    )
EXECUTE PROCEDURE set_order_contact_id_from_short_id();

--
-- table: update_domain_rem_contact
-- description: this table stores attributes of contact to be removed from domain.
--
CREATE TABLE update_domain_rem_contact (
    update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
    order_contact_id        UUID NOT NULL REFERENCES order_contact,
    domain_contact_type_id  UUID NOT NULL REFERENCES domain_contact_type,
    short_id                TEXT,
    PRIMARY KEY(update_domain_id,order_contact_id, domain_contact_type_id)
) INHERITS(class.audit);

CREATE OR REPLACE TRIGGER a_set_order_contact_id_from_short_id_tg
    BEFORE INSERT ON update_domain_rem_contact
    FOR EACH ROW WHEN (
    NEW.order_contact_id IS NULL AND
    NEW.short_id IS NOT NULL
    )
EXECUTE PROCEDURE set_order_contact_id_from_short_id();

CREATE TRIGGER order_prevent_if_update_domain_contact_does_not_exist_tg
    BEFORE INSERT ON update_domain_rem_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_update_domain_contact_does_not_exist();

--
-- table: update_domain_add_secdns
-- description: this table stores attributes of secdns to be added to domain.
--

CREATE TABLE update_domain_add_secdns (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
  ds_data_id              UUID REFERENCES order_secdns_ds_data,
  key_data_id             UUID REFERENCES order_secdns_key_data,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  )
) INHERITS(class.audit);

CREATE INDEX ON update_domain_add_secdns(update_domain_id);

CREATE TRIGGER update_domain_add_secdns_validate_record_unique_tg
  BEFORE INSERT ON update_domain_add_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_add_secdns_does_not_exist();

-- add trigger to validate the domain secdns data
CREATE TRIGGER validate_domain_secdns_data_tg
  BEFORE INSERT ON update_domain_add_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_domain_secdns_data();

--
-- table: update_domain_rem_secdns
-- description: this table stores attributes of secdns to be removed from domain.
--

CREATE TABLE update_domain_rem_secdns (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
  ds_data_id              UUID REFERENCES order_secdns_ds_data,
  key_data_id             UUID REFERENCES order_secdns_key_data,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  ) 
) INHERITS(class.audit);

CREATE INDEX ON update_domain_rem_secdns(update_domain_id);

CREATE TRIGGER update_domain_rem_secdns_validate_record_exists_tg
  BEFORE INSERT ON update_domain_rem_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_rem_secdns_exists();

-- this table contains the plan for creating a domain
CREATE TABLE update_domain_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_update_domain
) INHERITS(order_item_plan,class.audit_trail);

-- validates plan items for domain update host
CREATE TRIGGER validate_update_domain_host_plan_tg
    AFTER UPDATE ON update_domain_plan
    FOR EACH ROW WHEN (
      OLD.validation_status_id <> NEW.validation_status_id
      AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host')
    )
    EXECUTE PROCEDURE validate_update_domain_host_plan();

-- validates plan items for domain update
CREATE TRIGGER validate_update_domain_plan_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
  )
  EXECUTE PROCEDURE validate_update_domain_plan();

CREATE TRIGGER plan_update_domain_provision_host_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host') 
  )
  EXECUTE PROCEDURE plan_update_domain_provision_host();

CREATE TRIGGER plan_update_domain_provision_contact_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','contact')
  )
  EXECUTE PROCEDURE plan_update_domain_provision_contact();

CREATE TRIGGER plan_update_domain_provision_domain_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
  )
  EXECUTE PROCEDURE plan_update_domain_provision_domain();

-- host already provisioned just insert records accordingly
CREATE TRIGGER plan_update_domain_provision_host_skipped_tg 
  AFTER UPDATE ON update_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id = tc_id_from_name('order_item_plan_status','new')
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','completed')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host') 
  )
  EXECUTE PROCEDURE provision_domain_host_skipped();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();
