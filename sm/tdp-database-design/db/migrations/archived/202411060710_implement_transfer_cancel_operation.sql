-- add provision_domain_transfer_in_cancel_request job_type
INSERT INTO job_type(
  name,
  descr,
  reference_table,
  reference_status_table,
  reference_status_column,
  routing_key,
  is_noop
)
VALUES
(
  'provision_domain_transfer_in_cancel_request',
  'Submits domain transfer cancel request to the backend',
  'provision_domain_transfer_in_cancel_request',
  'provision_status',
  'status_id',
  'WorkerJobDomainProvision',
  FALSE
)
ON CONFLICT DO NOTHING;


-- function: provision_domain_transfer_away_job()
-- description: creates the job to submit transfer away action for the domain
CREATE OR REPLACE FUNCTION provision_domain_transfer_away_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_away   RECORD;
BEGIN
    SELECT
        NEW.id AS provision_domain_transfer_action_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.pw,
        pdt.order_metadata AS metadata,
        ts.name AS transfer_status
    INTO v_transfer_away
    FROM provision_domain_transfer_away pdt
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    JOIN transfer_status ts ON ts.id = NEW.transfer_status_id
    WHERE pdt.id = NEW.id;

    UPDATE provision_domain_transfer_away SET job_id=job_submit(
        v_transfer_away.tenant_customer_id,
        'provision_domain_transfer_away',
        NEW.id,
        TO_JSONB(v_transfer_away.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_transfer_in_cancel_request_job()
-- description: creates the job to cancel transfer in request for the domain
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_cancel_request_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in   RECORD;
BEGIN
    SELECT
        NEW.id AS provision_domain_transfer_action_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdtr.domain_name,
        pdtr.pw,
        pdtr.order_metadata AS metadata,
        'clientCancelled' AS transfer_status
    INTO v_transfer_in
    FROM provision_domain_transfer_in_cancel_request pdtcr
        JOIN provision_domain_transfer_in_request pdtr ON pdtr.id = pdtcr.transfer_in_request_id
        JOIN v_accreditation a ON a.accreditation_id = pdtr.accreditation_id
        JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pdtcr.id = NEW.id;

    UPDATE provision_domain_transfer_in_cancel_request SET job_id=job_submit(
        v_transfer_in.tenant_customer_id,
        'provision_domain_transfer_in_cancel_request',
        NEW.id,
        TO_JSONB(v_transfer_in.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_domain_transfer_in_cancel_request_success()
-- description: completes the transfer in cancel request
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_cancel_request_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE provision_domain_transfer_in_request SET 
      transfer_status_id = tc_id_from_name('transfer_status', 'clientCancelled'), 
      status_id = tc_id_from_name('provision_status', 'completed')
    WHERE id = NEW.transfer_in_request_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- table: provision_domain_transfer_in_cancel_request
-- description: this table is used to cancel transfer in request
--
CREATE TABLE IF NOT EXISTS provision_domain_transfer_in_cancel_request (
  transfer_in_request_id UUID NOT NULL REFERENCES provision_domain_transfer_in_request,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail, class.provision);

-- starts the domain transfer in cancel provision
CREATE OR REPLACE TRIGGER provision_domain_transfer_in_cancel_request_job_tg
  AFTER INSERT ON provision_domain_transfer_in_cancel_request
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_cancel_request_job();

-- completes the domain transfer in cancel provision
CREATE OR REPLACE TRIGGER provision_domain_transfer_in_cancel_request_success_tg
  AFTER UPDATE ON provision_domain_transfer_in_cancel_request
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_cancel_request_success();

-- order status notify on order cacellation failure
CREATE OR REPLACE TRIGGER provision_domain_transfer_in_cancel_request_failure_tg
  AFTER UPDATE ON provision_domain_transfer_in_cancel_request
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE provision_order_status_notify();

\i triggers.ddl
\i provisioning/triggers.ddl
