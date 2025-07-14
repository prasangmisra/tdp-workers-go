--
-- table: provision_contact_update
-- description: this table is to provision a update contact in a backend.
--

CREATE TABLE provision_contact_update (
  contact_id                UUID NOT NULL REFERENCES contact,
  order_contact_id          UUID NOT NULL REFERENCES order_contact,
  is_complete               BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY(id),
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer
) INHERITS (class.audit_trail,class.provision);

-- starts the contact update order provision
CREATE TRIGGER provision_contact_update_job_tg
  AFTER UPDATE ON provision_contact_update
  FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete
    AND NEW.is_complete 
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_contact_update_job();

CREATE TRIGGER provision_contact_update_success_tg
  AFTER UPDATE ON provision_contact_update
  FOR EACH ROW WHEN (
    NEW.is_complete
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_contact_update_success();

--
-- table: provision_domain_contact_update
-- description: This table is for provisioning a domain contact update in the backend. It does not inherit from the
-- class.provision to prevent the cleanup of failed provisions resulting from partially successful updates.
--
CREATE TABLE provision_domain_contact_update(
  id                              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_contact_update_id     UUID NOT NULL REFERENCES provision_contact_update
                                  ON DELETE CASCADE,
  contact_id                      UUID NOT NULL REFERENCES contact,
  order_contact_id                UUID NOT NULL REFERENCES order_contact,
  accreditation_id                UUID NOT NULL REFERENCES accreditation,
  handle                          TEXT,
  tenant_customer_id              UUID NOT NULL REFERENCES tenant_customer,
  status_id                       UUID NOT NULL DEFAULT tc_id_from_name('provision_status','pending'),
  job_id                          UUID REFERENCES job,
  UNIQUE(provision_contact_update_id,handle)
) INHERITS(class.audit_trail);
