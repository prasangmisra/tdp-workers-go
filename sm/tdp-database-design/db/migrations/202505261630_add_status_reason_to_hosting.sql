ALTER TABLE hosting
ADD COLUMN IF NOT EXISTS status_reason TEXT;

DROP VIEW IF EXISTS v_hosting;

CREATE OR REPLACE VIEW v_hosting AS
SELECT
    h.*,
    tc_name_from_id('hosting_status', h.hosting_status_id) AS status
FROM ONLY hosting h;

-- function: order_item_create_hosting_record()
-- description: creates the hosting object which we will manipulate during order processing
CREATE OR REPLACE FUNCTION order_item_create_hosting_record() RETURNS TRIGGER AS $$
DECLARE
    v_hosting_client RECORD;
BEGIN

    SELECT * INTO v_hosting_client
    FROM hosting_client
    WHERE id = NEW.client_id;

    INSERT INTO hosting_client (
        id,
        tenant_customer_id,
        external_client_id,
        name,
        email,
        username,
        password,
        is_active
    ) VALUES (
                 v_hosting_client.id,
                 v_hosting_client.tenant_customer_id,
                 v_hosting_client.external_client_id,
                 v_hosting_client.name,
                 v_hosting_client.email,
                 v_hosting_client.username,
                 v_hosting_client.password,
                 v_hosting_client.is_active
             ) ON CONFLICT DO NOTHING;

    IF NEW.certificate_id IS NOT NULL THEN
        INSERT INTO hosting_certificate (
            SELECT * FROM hosting_certificate WHERE id=NEW.certificate_id
        );
    END IF;

    -- insert all the values from new into hosting
    INSERT INTO hosting (
        id,
        domain_name,
        product_id,
        region_id,
        client_id,
        tenant_customer_id,
        certificate_id,
        external_order_id,
        hosting_status_id,
        descr,
        is_active,
        is_deleted,
        tags,
        metadata,
        status_reason
    )
    VALUES (
               NEW.id,
               NEW.domain_name,
               NEW.product_id,
               NEW.region_id,
               NEW.client_id,
               NEW.tenant_customer_id,
               NEW.certificate_id,
               NEW.external_order_id,
               NEW.hosting_status_id,
               NEW.descr,
               NEW.is_active,
               NEW.is_deleted,
               NEW.tags,
               NEW.metadata,
               null
           );

    RETURN NEW;
END $$ LANGUAGE plpgsql;

-- function: mark_hosting_record_failed
-- description: marks a hosting record as failed and sets is_deleted to true
CREATE OR REPLACE FUNCTION mark_hosting_record_failed() RETURNS TRIGGER AS $$
DECLARE
    v_result_message TEXT;
BEGIN
    -- Step 1: Get the result_message from the job
    SELECT result_message INTO v_result_message
    FROM job
    WHERE id = NEW.job_id;

    UPDATE ONLY hosting
    SET
        hosting_status_id = tc_id_from_name('hosting_status', 'Failed'),
        is_deleted = TRUE,
        status_reason = v_result_message
    WHERE id = NEW.hosting_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update a hosting record if sending the hosting request to SAAS fails
CREATE TRIGGER provision_hosting_update_failure_tg
    AFTER UPDATE ON provision_hosting_update
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id AND
        NEW.status_id = tc_id_from_name('provision_status', 'failed')
    ) EXECUTE PROCEDURE mark_hosting_record_failed();