--
-- table: provision_contact
-- description: this table stores backend provider contact handles and joins it to contact and backend_provider_tld.
--

CREATE TABLE provision_contact (
  contact_id              UUID NOT NULL REFERENCES contact,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  accreditation_tld_id    UUID REFERENCES accreditation_tld,
  domain_contact_type_id  UUID REFERENCES domain_contact_type,
  handle                  TEXT,
  pw                      TEXT NOT NULL DEFAULT TC_GEN_PASSWORD(16),
  PRIMARY KEY(id),
  UNIQUE (contact_id, accreditation_id),
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer
) INHERITS (class.audit_trail,class.provision);

-- starts the contact create order provision
CREATE TRIGGER provision_contact_job_tg
  AFTER INSERT ON provision_contact
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_contact_job();
