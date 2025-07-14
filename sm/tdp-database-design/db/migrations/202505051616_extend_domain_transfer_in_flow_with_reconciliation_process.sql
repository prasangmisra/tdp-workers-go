-- function: provision_domain_transfer_in_job()
-- description: creates the job to fetch transferred domain data
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in  RECORD;
    _start_date    TIMESTAMPTZ;
BEGIN
    SELECT
        NEW.id AS provision_domain_transfer_in_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.order_metadata AS metadata
    INTO v_transfer_in
    FROM provision_domain_transfer_in pdt
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pdt.id = NEW.id;

    _start_date := job_start_date(NEW.attempt_count);

    UPDATE provision_domain_transfer_in SET job_id=job_submit(
        v_transfer_in.tenant_customer_id,
        'provision_domain_transfer_in',
        NEW.id,
        TO_JSONB(v_transfer_in.*),
        NULL,
        _start_date
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- keeps status the same when retrying is needed
CREATE OR REPLACE TRIGGER keep_provision_status_for_retry_tg
  BEFORE UPDATE ON provision_domain_transfer_in
  FOR EACH ROW WHEN (
    OLD.attempt_count = NEW.attempt_count
    AND NEW.attempt_count < NEW.allowed_attempts
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE keep_provision_status_and_increment_attempt_count();


-- retries the domain transfer in provision
CREATE OR REPLACE TRIGGER provision_domain_transfer_in_retry_tg
  AFTER UPDATE ON provision_domain_transfer_in
  FOR EACH ROW WHEN (
    OLD.attempt_count <> NEW.attempt_count
    AND NEW.attempt_count <= NEW.allowed_attempts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_job();
