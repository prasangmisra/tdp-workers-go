--
-- table: provision_domain_transfer_away
-- description: this table is used to process transfer away approve/reject 
--

CREATE TABLE provision_domain_transfer_away (
    domain_id               UUID,
    domain_name             FQDN NOT NULL,
    pw                      TEXT,
    transfer_status_id      UUID NOT NULL REFERENCES transfer_status,
    accreditation_id        UUID NOT NULL REFERENCES accreditation,
    accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
    FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
    PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

-- starts the domain transfer away provision
CREATE TRIGGER provision_domain_transfer_away_job_tg
  AFTER INSERT ON provision_domain_transfer_away
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
      AND NEW.transfer_status_id IN (tc_id_from_name('transfer_status','clientRejected'),
                                     tc_id_from_name('transfer_status','clientApproved'))
  ) EXECUTE PROCEDURE provision_domain_transfer_away_job();

-- trigger when the operation is successful
CREATE TRIGGER provision_domain_transfer_away_success_tg
    AFTER UPDATE ON provision_domain_transfer_away
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('provision_status','completed')
        AND NEW.transfer_status_id IN (tc_id_from_name('transfer_status','serverApproved'),
                                       tc_id_from_name('transfer_status','clientApproved'))
    ) EXECUTE PROCEDURE provision_domain_transfer_away_success();

