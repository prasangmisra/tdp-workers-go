--
-- table: provision_host_delete
-- description: this table is for provisioning a domain host delete in the backend.
--

CREATE TABLE provision_host_delete (
  host_id                 UUID NOT NULL,
  name                    TEXT NOT NULL,
  domain_id               UUID REFERENCES domain,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

-- starts the host delete order provision
CREATE TRIGGER provision_host_delete_job_tg
  AFTER INSERT ON provision_host_delete
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_host_delete_job();

-- completes the host delete order provision
CREATE TRIGGER provision_host_delete_success_tg
  AFTER UPDATE ON provision_host_delete
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_host_delete_success();
