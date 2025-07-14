CREATE OR REPLACE FUNCTION cancel_hosting_provision(_hosting_id UUID) RETURNS void AS $$
DECLARE
    _provision_hosting_certificate_create RECORD;
    _provision_hosting_dns_check_job RECORD;
    _provision_hosting_certificate_create_job RECORD;
BEGIN
    -- find coresponsding provision record
    SELECT * INTO _provision_hosting_certificate_create
    FROM provision_hosting_certificate_create phcc
    JOIN provision_status ps ON ps.id = phcc.status_id
    WHERE phcc.hosting_id = _hosting_id
        AND ps.is_final = FALSE
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hosting provisioning cannot be cancelled at this stage' USING ERRCODE = 'data_exception';
    END IF;

    -- mark provision record as failed
    UPDATE provision_hosting_certificate_create
    SET status_id = tc_id_from_name('provision_status', 'failed')
    WHERE id = _provision_hosting_certificate_create.id;

    -- override hosting status
    UPDATE ONLY hosting SET status = 'Cancelled' WHERE id = _provision_hosting_certificate_create.hosting_id;

    -- cleanup jobs
    SELECT * INTO _provision_hosting_dns_check_job
    FROM job
    WHERE reference_id = _provision_hosting_certificate_create.id
    AND type_id = tc_id_from_name('job_type', 'provision_hosting_dns_check')
    AND NOT EXISTS (
        SELECT 1
        FROM job_status js
        WHERE js.id = job.status_id
        AND js.is_final = TRUE
    ) FOR UPDATE;

    IF FOUND THEN
        -- mark dns check job as failed and prevent from starting again
        UPDATE job SET
            status_id = tc_id_from_name('job_status', 'failed'),
            retry_count = max_retries
        WHERE id = _provision_hosting_dns_check_job.id;
    END IF;

    SELECT * INTO _provision_hosting_certificate_create_job
    FROM job
    WHERE reference_id = _provision_hosting_certificate_create.id
    AND type_id = tc_id_from_name('job_type', 'provision_hosting_certificate_create')
    AND NOT EXISTS (
        SELECT 1
        FROM job_status js
        WHERE js.id = job.status_id
        AND js.is_final = TRUE
    ) FOR UPDATE;

    IF FOUND THEN
        -- mark create certificate job as failed
        UPDATE job SET
            status_id = tc_id_from_name('job_status', 'failed')
        WHERE id = _provision_hosting_certificate_create_job.id;
    END IF;

END;
$$ LANGUAGE plpgsql;
