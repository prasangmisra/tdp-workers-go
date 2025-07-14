--
-- table: provision_host
-- description: this table is to provision a host in a backend.
--

CREATE TABLE provision_host (
  host_id                 UUID NOT NULL,
  name                    TEXT NOT NULL,
  domain_id               UUID,
  addresses               INET[],
  tags                    TEXT[],
  metadata                JSONB DEFAULT '{}'::JSONB,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  PRIMARY KEY(id),
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer
) INHERITS (class.audit_trail,class.provision);

-- starts the host create order provision
CREATE TRIGGER provision_host_job_tg
  AFTER INSERT ON provision_host
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_host_job();

-- completes the host create order provision
CREATE TRIGGER provision_host_success_tg
  BEFORE UPDATE ON provision_host
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_host_success();
