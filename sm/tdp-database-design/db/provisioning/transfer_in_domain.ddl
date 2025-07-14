--
-- table: provision_domain_transfer_in_request
-- description: this table is used to create and track transfer in request
--

CREATE TABLE provision_domain_transfer_in_request (
  domain_name             FQDN NOT NULL,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
  pw                      TEXT,
  transfer_period         INT NOT NULL DEFAULT 1,
  transfer_status_id      UUID NOT NULL DEFAULT tc_id_from_name('transfer_status','pending') 
                          REFERENCES transfer_status,
  requested_by            TEXT,
  requested_date          TIMESTAMPTZ,
  action_by               TEXT,
  action_date             TIMESTAMPTZ,
  expiry_date             TIMESTAMPTZ,
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

-- keeps status the same when retrying is needed
CREATE OR REPLACE TRIGGER keep_provision_status_for_retry_tg
  BEFORE UPDATE ON provision_domain_transfer_in_request
  FOR EACH ROW WHEN (
    OLD.attempt_count = NEW.attempt_count
    AND NEW.attempt_count < NEW.allowed_attempts
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE keep_provision_status_and_increment_attempt_count();

-- starts the domain transfer in request provision
CREATE TRIGGER provision_domain_transfer_in_request_job_tg
  AFTER INSERT ON provision_domain_transfer_in_request
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_request_job();

-- retries the domain transfer in request provision
CREATE OR REPLACE TRIGGER provision_domain_transfer_in_request_retry_tg
  AFTER UPDATE ON provision_domain_transfer_in_request
  FOR EACH ROW WHEN (
    OLD.attempt_count <> NEW.attempt_count
    AND NEW.attempt_count <= NEW.allowed_attempts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_request_job();

CREATE TRIGGER provision_domain_transfer_in_request_order_notify_tg
  AFTER UPDATE ON provision_domain_transfer_in_request
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();

CREATE TRIGGER event_domain_transfer_in_request_tg
    AFTER UPDATE OF transfer_status_id ON provision_domain_transfer_in_request
    FOR EACH ROW
    WHEN (NEW.transfer_status_id IS NOT NULL)
EXECUTE PROCEDURE event_domain_transfer_in_request();

--
-- table: provision_domain_transfer_in
-- description: this table is used to finalize transfer_in domain provisioning
--
CREATE TYPE secdns_data_type AS ENUM ('ds_data', 'key_data');

CREATE TABLE provision_domain_transfer_in (
  domain_name             FQDN NOT NULL,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
  provision_transfer_request_id UUID REFERENCES provision_domain_transfer_in_request,
  pw                      TEXT,
  ry_created_date         TIMESTAMPTZ,
  ry_expiry_date          TIMESTAMPTZ,
  ry_updated_date         TIMESTAMPTZ,
  ry_transfered_date      TIMESTAMPTZ,
  hosts                   FQDN[],
  tags                    TEXT[],
  uname                   TEXT,
  language                TEXT,
  metadata                JSONB DEFAULT '{}'::JSONB,
  secdns_type             secdns_data_type,
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

-- keeps status the same when retrying is needed
CREATE OR REPLACE TRIGGER keep_provision_status_for_retry_tg
  BEFORE UPDATE ON provision_domain_transfer_in
  FOR EACH ROW WHEN (
    OLD.attempt_count = NEW.attempt_count
    AND NEW.attempt_count < NEW.allowed_attempts
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE keep_provision_status_and_increment_attempt_count();

-- starts the domain transfer in provision
CREATE TRIGGER provision_domain_transfer_in_job_tg
  AFTER INSERT ON provision_domain_transfer_in
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_job();

-- retries the domain transfer in provision
CREATE OR REPLACE TRIGGER provision_domain_transfer_in_retry_tg
  AFTER UPDATE ON provision_domain_transfer_in
  FOR EACH ROW WHEN (
    OLD.attempt_count <> NEW.attempt_count
    AND NEW.attempt_count <= NEW.allowed_attempts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_job();

CREATE TRIGGER provision_domain_transfer_in_success_tg
  AFTER UPDATE ON provision_domain_transfer_in
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_success();

CREATE TABLE transfer_in_domain_secdns_ds_data (
    provision_domain_transfer_in_id UUID NOT NULL REFERENCES provision_domain_transfer_in,
    PRIMARY KEY(id)
)INHERITS(secdns_ds_data);

CREATE TABLE transfer_in_domain_secdns_key_data (
    provision_domain_transfer_in_id UUID NOT NULL REFERENCES provision_domain_transfer_in,
    PRIMARY KEY(id)
)INHERITS(secdns_key_data);

-- Composite index for domain_id and ds_data_id
CREATE INDEX idx_transfer_in_domain_secdns_domain_ds
    ON transfer_in_domain_secdns_ds_data(provision_domain_transfer_in_id);

-- Composite index for domain_id and key_data_id
CREATE INDEX idx_transfer_in_domain_secdns_domain_key
    ON transfer_in_domain_secdns_key_data(provision_domain_transfer_in_id);


--
-- table: provision_domain_transfer_in_cancel_request
-- description: this table is used to cancel transfer in request
--
CREATE TABLE provision_domain_transfer_in_cancel_request (
  transfer_in_request_id UUID NOT NULL REFERENCES provision_domain_transfer_in_request,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail, class.provision);

-- starts the domain transfer in cancel provision
CREATE TRIGGER provision_domain_transfer_in_cancel_request_job_tg
  AFTER INSERT ON provision_domain_transfer_in_cancel_request
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_cancel_request_job();

-- completes the domain transfer in cancel provision
CREATE TRIGGER provision_domain_transfer_in_cancel_request_success_tg
  AFTER UPDATE ON provision_domain_transfer_in_cancel_request
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_cancel_request_success();

-- order status notify on order cacellation failure
CREATE TRIGGER provision_domain_transfer_in_cancel_request_failure_tg
  AFTER UPDATE ON provision_domain_transfer_in_cancel_request
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE provision_order_status_notify();
