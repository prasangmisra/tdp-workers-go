--
-- table: provision_domain_redeem
-- description: this table is to redeem.
--
-- this table will hold all the info that needs to be sent to the ry
-- have optional fields with the set of all possible data needed for redeem report,
-- will send specific data per TLD based on TLD settings

CREATE TABLE provision_domain_redeem (
  domain_id               UUID REFERENCES domain ON DELETE CASCADE,
  domain_name             FQDN NOT NULL,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  ry_cltrid               TEXT,
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);


-- starts the domain redeem order provision
CREATE TRIGGER provision_domain_redeem_job_tg
  AFTER INSERT ON provision_domain_redeem
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_redeem_job();

CREATE TRIGGER provision_domain_redeem_success_tg
  AFTER UPDATE ON provision_domain_redeem
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_redeem_success();


CREATE TRIGGER provision_domain_redeem_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain_redeem
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();
