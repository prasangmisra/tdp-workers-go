-- function: provision_domain_delete_job()
-- description: creates the job to delete the domain
CREATE OR REPLACE FUNCTION provision_domain_delete_job() RETURNS TRIGGER AS $$
DECLARE
    v_delete        RECORD;
    _pddh           RECORD;
    _parent_job_id  UUID;
    _start_date     TIMESTAMPTZ;
BEGIN
    SELECT
        NEW.id AS provision_domain_delete_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pd.domain_name AS domain_name,
        pd.in_redemption_grace_period,
        pd.order_metadata AS metadata
    INTO v_delete
    FROM provision_domain_delete pd
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pd.id = NEW.id;

    SELECT job_create(
        v_delete.tenant_customer_id,
        'provision_domain_delete',
        NEW.id,
        TO_JSONB(v_delete.*)
    ) INTO _parent_job_id;

    UPDATE provision_domain_delete SET job_id= _parent_job_id WHERE id=NEW.id;

    _start_date := job_start_date(NEW.attempt_count);

    PERFORM job_submit(
        v_delete.tenant_customer_id,
        'setup_domain_delete',
        NEW.id,
        TO_JSONB(v_delete.*),
        _parent_job_id,
        _start_date
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- keeps status the same when retrying is needed
CREATE OR REPLACE TRIGGER keep_provision_status_for_retry_tg
  BEFORE UPDATE ON provision_domain_delete
  FOR EACH ROW WHEN (
    OLD.attempt_count = NEW.attempt_count
    AND NEW.attempt_count < NEW.allowed_attempts
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE keep_provision_status_and_increment_attempt_count();


-- retries the domain delete order provision
CREATE OR REPLACE TRIGGER provision_domain_retry_job_tg
  AFTER UPDATE ON provision_domain_delete
  FOR EACH ROW WHEN (
    OLD.attempt_count <> NEW.attempt_count
    AND NEW.attempt_count <= NEW.allowed_attempts
    AND NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_delete_job();
