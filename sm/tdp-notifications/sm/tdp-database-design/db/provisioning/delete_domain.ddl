--
-- table: provision_domain_delete
-- description: this table is to delete domain in a backend.
--

CREATE TABLE provision_domain_delete (
  domain_id                     UUID REFERENCES domain ON DELETE CASCADE,
  domain_name                   FQDN NOT NULL,
  accreditation_id              UUID NOT NULL REFERENCES accreditation,
  ry_cltrid                     TEXT,
  in_redemption_grace_period    BOOLEAN NOT NULL DEFAULT FALSE,
  hosts                         TEXT[],
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

-- starts the domain delete order provision
CREATE TRIGGER provision_domain_delete_job_tg
  AFTER INSERT ON provision_domain_delete
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_delete_job();

CREATE TRIGGER provision_domain_hosts_delete_job_tg
  AFTER UPDATE ON provision_domain_delete
  FOR EACH ROW WHEN (
    OLD.hosts IS DISTINCT FROM NEW.hosts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_hosts_delete_job();

CREATE TRIGGER provision_domain_delete_success_tg
  AFTER UPDATE ON provision_domain_delete
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_delete_success();

CREATE TRIGGER provision_domain_delete_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain_delete
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();


CREATE TABLE provision_domain_delete_host(
  id                            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_delete_id    UUID NOT NULL REFERENCES provision_domain_delete
                                ON DELETE CASCADE,
  host_name                     TEXT NOT NULL,
  UNIQUE(provision_domain_delete_id,host_name)
) INHERITS(class.audit,class.provision);


CREATE TRIGGER provision_domain_delete_host_success_tg
  AFTER UPDATE ON provision_domain_delete_host
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_delete_host_success();
