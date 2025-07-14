--
-- table: provision_domain_renew
-- description: this table is to provision a domain in a backend.
--

CREATE TABLE provision_domain_renew (
  domain_id               UUID REFERENCES domain ON DELETE CASCADE,
  domain_name             FQDN NOT NULL,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  period                  INT NOT NULL DEFAULT 1,
  current_expiry_date     TIMESTAMPTZ NOT NULL,
  is_auto                 BOOLEAN NOT NULL DEFAULT FALSE,
  ry_expiry_date          TIMESTAMPTZ,        -- set after successful
  ry_cltrid               TEXT,
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);


CREATE TRIGGER provision_domain_renew_check_exp_date_tg
  BEFORE INSERT ON provision_domain_renew
  FOR EACH ROW EXECUTE PROCEDURE provision_domain_renew_check_exp_date();

-- keeps status the same when retrying is needed
CREATE OR REPLACE TRIGGER keep_provision_status_for_retry_tg
  BEFORE UPDATE ON provision_domain_renew
  FOR EACH ROW WHEN (
    OLD.attempt_count = NEW.attempt_count
    AND NEW.attempt_count < NEW.allowed_attempts
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE keep_provision_status_and_increment_attempt_count();

-- starts the domain renew order provision
CREATE TRIGGER provision_domain_renew_job_tg
  AFTER INSERT ON provision_domain_renew
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_renew_job();

-- retries the domain renew order provision
CREATE OR REPLACE TRIGGER provision_domain_renew_retry_job_tg
  AFTER UPDATE ON provision_domain_renew
  FOR EACH ROW WHEN (
    OLD.attempt_count <> NEW.attempt_count
    AND NEW.attempt_count <= NEW.allowed_attempts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_renew_job();

-- COMMENT ON TRIGGER provision_domain_renew_job_tg IS 'creates a job when the provision data is complete';

CREATE TRIGGER provision_domain_renew_success_tg
  AFTER UPDATE ON provision_domain_renew
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_renew_success();

CREATE TRIGGER provision_domain_renew_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain_renew
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();
