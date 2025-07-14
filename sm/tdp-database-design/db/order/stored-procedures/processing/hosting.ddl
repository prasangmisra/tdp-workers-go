-- function: plan_create_hosting_certificate_provision()
-- description: creates provision_hosting_certificate record to trigger job
CREATE OR REPLACE FUNCTION plan_create_hosting_certificate_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_hosting RECORD;
    v_create_hosting_certificate RECORD;
BEGIN

    SELECT * INTO v_create_hosting
    FROM v_order_create_hosting
    WHERE order_item_id = NEW.order_item_id;

    IF v_create_hosting.certificate_id IS NOT NULL THEN
        UPDATE create_hosting_plan
        SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
        WHERE id = NEW.id;
    ELSE
        INSERT INTO provision_hosting_certificate_create (
            domain_name,
            hosting_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES (
                     v_create_hosting.domain_name,
                     v_create_hosting.hosting_id,
                     v_create_hosting.tenant_customer_id,
                     v_create_hosting.order_metadata,
                     ARRAY[NEW.id]
                 );


    END IF;


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_create_hosting_provision()
-- description: creates provision_hosting_create record to trigger job
CREATE OR REPLACE FUNCTION plan_create_hosting_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_hosting   RECORD;
BEGIN
    SELECT * INTO v_create_hosting
    FROM v_order_create_hosting
    WHERE order_item_id = NEW.order_item_id;

    INSERT INTO provision_hosting_create (
        hosting_id,
        domain_name,
        region_id,
        client_id,
        product_id,
        certificate_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
                 v_create_hosting.hosting_id,
                 v_create_hosting.domain_name,
                 v_create_hosting.region_id,
                 v_create_hosting.client_id,
                 v_create_hosting.product_id,
                 v_create_hosting.certificate_id,
                 v_create_hosting.tenant_customer_id,
                 v_create_hosting.order_metadata,
                 ARRAY[NEW.id]
             );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_delete_hosting_provision()
-- description: creates provision_hosting_delete record to trigger job
CREATE OR REPLACE FUNCTION plan_delete_hosting_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_hosting   RECORD;
BEGIN

    SELECT * INTO v_delete_hosting
    FROM v_order_delete_hosting
    WHERE order_item_id = NEW.order_item_id;

    INSERT INTO provision_hosting_delete (
        hosting_id,
        external_order_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
                 v_delete_hosting.hosting_id,
                 v_delete_hosting.external_order_id,
                 v_delete_hosting.tenant_customer_id,
                 v_delete_hosting.order_metadata,
                 ARRAY[NEW.id]
             );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_hosting_provision()
-- description: creates provision_hosting_update record to trigger job
CREATE OR REPLACE FUNCTION plan_update_hosting_provision() RETURNS TRIGGER AS $$
DECLARE
    v_update_hosting   RECORD;
BEGIN

    SELECT * INTO v_update_hosting
    FROM v_order_update_hosting
    WHERE order_item_id = NEW.order_item_id;

    INSERT INTO hosting_certificate (SELECT * FROM hosting_certificate WHERE id=v_update_hosting.certificate_id);

    INSERT INTO provision_hosting_update (
        hosting_id,
        is_active,
        certificate_id,
        external_order_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
                 v_update_hosting.hosting_id,
                 v_update_hosting.is_active,
                 v_update_hosting.certificate_id,
                 v_update_hosting.external_order_id,
                 v_update_hosting.tenant_customer_id,
                 v_update_hosting.order_metadata,
                 ARRAY[NEW.id]
             );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: cancel_hosting_provision()
-- description: cancels hosting provisioning at certificate provisioning stage
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
    UPDATE ONLY hosting
    SET hosting_status_id = tc_id_from_name('hosting_status', 'Cancelled')
    WHERE id = _provision_hosting_certificate_create.hosting_id;

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
