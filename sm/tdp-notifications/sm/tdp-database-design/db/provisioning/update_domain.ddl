--
-- table: provision_domain_update
-- description: this table is to provision a domain in a backend.
--

CREATE TABLE provision_domain_update (
  domain_id               UUID REFERENCES domain ON DELETE CASCADE,
  domain_name             FQDN NOT NULL,
  auth_info               TEXT,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
  is_complete             BOOLEAN NOT NULL DEFAULT FALSE,
  auto_renew              BOOLEAN,
  ry_cltrid               TEXT,
  locks                   JSONB,
  secdns_max_sig_life     INT,
  PRIMARY KEY(id),
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer
) INHERITS (class.audit_trail,class.provision);

--
-- table: provision_domain_update_add_secdns
-- description: this table holds secdns data to add on domain update.
--


CREATE TABLE provision_domain_update_add_secdns (
  id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id  UUID NOT NULL REFERENCES provision_domain_update 
                              ON DELETE CASCADE,
  secdns_id                   UUID NOT NULL REFERENCES update_domain_add_secdns
) INHERITS(class.audit_trail);

--
-- table: provision_domain_update_rem_secdns
-- description: this table holds secdns data to remove on domain update.
--


CREATE TABLE provision_domain_update_rem_secdns (
  id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id  UUID NOT NULL REFERENCES provision_domain_update 
                              ON DELETE CASCADE,
  secdns_id                   UUID NOT NULL REFERENCES update_domain_rem_secdns
) INHERITS(class.audit_trail);


-- starts the domain update order provision
CREATE TRIGGER provision_domain_update_job_tg
  AFTER UPDATE ON provision_domain_update
  FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete 
    AND NEW.is_complete 
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_update_job();

-- COMMENT ON TRIGGER provision_domain_update_job_tg IS 'creates a job when the provision data is complete';

CREATE TRIGGER provision_domain_update_success_tg
  AFTER UPDATE ON provision_domain_update
  FOR EACH ROW WHEN (
    NEW.is_complete
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_update_success();

-- COMMENT ON TRIGGER provision_domain_update_success_tg IS 'creates the domain after the provision_domain_update is done';

CREATE TRIGGER provision_domain_update_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain_update
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();

--
-- table: provision_domain_update_contact
-- description: this table is to update a domain contact association in a backend.
--

CREATE TABLE provision_domain_update_contact(
  id                                UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id        UUID NOT NULL REFERENCES provision_domain_update
                                    ON DELETE CASCADE,
  contact_id                        UUID NOT NULL REFERENCES contact,
  contact_type_id                   UUID NOT NULL REFERENCES domain_contact_type,
  UNIQUE(provision_domain_update_id,contact_id,contact_type_id)
) INHERITS(class.audit);

--
-- table: provision_domain_update_add_host
-- description: this table is to add a domain nameserver association in a backend.
--

CREATE TABLE provision_domain_update_add_host (
  id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id  UUID NOT NULL REFERENCES provision_domain_update 
                              ON DELETE CASCADE,
  host_id                     UUID NOT NULL REFERENCES host
                              ON DELETE CASCADE
) INHERITS(class.audit_trail);

--
-- table: provision_domain_update_rem_host
-- description: this table is to remove a domain nameserver association in a backend.
--

CREATE TABLE provision_domain_update_rem_host (
  id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id  UUID NOT NULL REFERENCES provision_domain_update 
                              ON DELETE CASCADE,
  host_id                     UUID NOT NULL REFERENCES host
                              ON DELETE CASCADE
) INHERITS(class.audit_trail);

--
-- table: provision_domain_update_add_contact
-- description: this table is to add domain contact association in a backend.
--
CREATE TABLE provision_domain_update_add_contact (
   provision_domain_update_id        UUID NOT NULL REFERENCES provision_domain_update
       ON DELETE CASCADE,
   contact_id                        UUID NOT NULL REFERENCES contact,
   contact_type_id                   UUID NOT NULL REFERENCES domain_contact_type,
   PRIMARY KEY (provision_domain_update_id,contact_id,contact_type_id)
) INHERITS(class.audit);

--
-- table: provision_domain_update_rem_contact
-- description: this table is to remove domain contact association in a backend.
--
CREATE TABLE provision_domain_update_rem_contact (
     provision_domain_update_id        UUID NOT NULL REFERENCES provision_domain_update
         ON DELETE CASCADE,
     contact_id                        UUID NOT NULL REFERENCES contact,
     contact_type_id                   UUID NOT NULL REFERENCES domain_contact_type,
     PRIMARY KEY (provision_domain_update_id,contact_id,contact_type_id)
) INHERITS(class.audit);

