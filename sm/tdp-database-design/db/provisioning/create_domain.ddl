--
-- table: provision_domain
-- description: this table is to provision a domain in a backend.
--

CREATE TABLE provision_domain (
  domain_name             FQDN NOT NULL,
  registration_period     INT NOT NULL DEFAULT 1,
  pw                      TEXT NOT NULL DEFAULT TC_GEN_PASSWORD(16),
  is_complete             BOOLEAN NOT NULL DEFAULT FALSE,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
  ry_created_date         TIMESTAMPTZ,
  ry_expiry_date          TIMESTAMPTZ,
  ry_cltrid               TEXT,
  auto_renew              BOOLEAN NOT NULL DEFAULT TRUE,
  secdns_max_sig_life     INT,
  uname                   TEXT,
  language                TEXT,
  launch_data             JSONB,
  tags                    TEXT[],
  metadata                JSONB DEFAULT '{}'::JSONB,
  parent_id               UUID REFERENCES provision_domain_update ON DELETE CASCADE,
  PRIMARY KEY(id),
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer
) INHERITS (class.audit_trail,class.provision);

-- keeps status the same when retrying is needed
CREATE OR REPLACE TRIGGER keep_provision_status_for_retry_tg
  BEFORE UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    OLD.attempt_count = NEW.attempt_count
    AND NEW.attempt_count < NEW.allowed_attempts
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE keep_provision_status_and_increment_attempt_count();

-- starts the domain create order provision
CREATE TRIGGER provision_domain_job_tg
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete
    AND NEW.is_complete
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_job();

-- retries the domain create order provision
CREATE OR REPLACE TRIGGER provision_domain_retry_job_tg
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    OLD.attempt_count <> NEW.attempt_count
    AND NEW.attempt_count <= NEW.allowed_attempts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_job();

-- COMMENT ON TRIGGER provision_domain_job_tg IS 'creates a job when the provision data is complete';

CREATE TRIGGER provision_domain_success_tg
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    NEW.is_complete 
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_success();

-- COMMENT ON TRIGGER provision_domain_success_tg IS 'creates the domain after the provision_domain is done';

CREATE TRIGGER provision_domain_failure_tg
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    NEW.is_complete 
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE provision_domain_failure();

-- COMMENT ON TRIGGER provision_domain_failure_tg IS 'fail the provision domain';

CREATE TRIGGER provision_domain_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();

CREATE TABLE provision_domain_contact(
  id                         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_id        UUID NOT NULL REFERENCES provision_domain 
                             ON DELETE CASCADE,
  contact_id                 UUID NOT NULL REFERENCES contact,
  contact_type_id            UUID NOT NULL REFERENCES domain_contact_type,
  UNIQUE(provision_domain_id,contact_id,contact_type_id)
) INHERITS(class.audit);

CREATE TABLE provision_domain_host(
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_id     UUID NOT NULL REFERENCES provision_domain
                          ON DELETE CASCADE,
  host_id                 UUID NOT NULL REFERENCES host
                          ON DELETE CASCADE,
  UNIQUE(provision_domain_id,host_id)
) INHERITS(class.audit);

--
-- table: provision_domain_secdns
-- description: this table holds secdns data to be added domain
--

CREATE TABLE provision_domain_secdns(
  id                     UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_id    UUID NOT NULL REFERENCES provision_domain 
                         ON DELETE CASCADE,
  secdns_id              UUID NOT NULL REFERENCES create_domain_secdns
) INHERITS(class.audit);
