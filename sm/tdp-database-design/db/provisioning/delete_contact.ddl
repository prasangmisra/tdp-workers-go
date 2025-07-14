
--
-- table: provision_contact_delete
-- description: this table is to delete contact in a backend.
--

CREATE TABLE provision_contact_delete (
  parent_id                       UUID REFERENCES provision_contact_delete ON DELETE CASCADE,
  contact_id                      UUID NOT NULL REFERENCES contact,
  accreditation_id                UUID REFERENCES accreditation,
  handle                          TEXT,
  is_complete                     BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

CREATE INDEX idx_parent_id ON provision_contact_delete (parent_id);

-- starts the contact delete order provision
CREATE TRIGGER provision_contact_delete_job_tg
  AFTER UPDATE ON provision_contact_delete
  FOR EACH ROW WHEN (
    OLD.is_complete <> NEW.is_complete
    AND NEW.is_complete 
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_contact_delete_job();

CREATE TRIGGER provision_contact_delete_success_tg
  AFTER UPDATE ON provision_contact_delete
  FOR EACH ROW WHEN (
    NEW.is_complete
    AND OLD.status_id <> NEW.status_id AND NEW.parent_id IS NULL
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_contact_delete_success();
