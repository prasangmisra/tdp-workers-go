--
-- table: provision_host_update
-- description: This table is for provisioning a domain host update in the backend.
--

CREATE TABLE provision_host_update (
  host_id                 UUID NOT NULL REFERENCES host ON DELETE CASCADE,
  name                    TEXT NOT NULL,  
  domain_id               UUID REFERENCES domain,
  addresses               INET[],
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

-- starts the host update order provision
CREATE TRIGGER provision_host_update_job_tg
  AFTER INSERT ON provision_host_update
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_host_update_job();

-- completes the host update order provision
CREATE TRIGGER provision_host_update_success_tg
  AFTER UPDATE ON provision_host_update
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_host_update_success();
