-- function: provision_finish()
-- description: finalizes the provisioning (or handles failure)
CREATE OR REPLACE FUNCTION provision_finish() RETURNS TRIGGER AS $$
DECLARE
    v_status      RECORD;
BEGIN

    SELECT * INTO v_status FROM provision_status WHERE id = NEW.status_id;

    IF NOT v_status.is_final THEN
        RETURN NEW;
    END IF;

    -- notify all the order_item_plan_ids that are pending
    IF NEW.order_item_plan_ids IS NOT NULL THEN
        -- Pre-cache values from job table once
        WITH job_data AS (
            SELECT result_data, result_message
            FROM job
            WHERE id = NEW.job_id
        )
        UPDATE order_item_plan
        SET
            status_id = (
                SELECT id
                FROM order_item_plan_status
                WHERE is_success = v_status.is_success
                  AND is_final
            ),
            result_data = COALESCE(NEW.result_data, (SELECT result_data FROM job_data)),
            result_message = COALESCE(NEW.result_message, (SELECT result_message FROM job_data))
        WHERE id = ANY(NEW.order_item_plan_ids);
    END IF;

    IF v_status.is_success THEN
        EXECUTE 'UPDATE ' || TG_TABLE_NAME || ' SET provisioned_date=NOW() WHERE id = $1'
  	    USING NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_cleanup()
-- description: either sets the provisioned_date OR deletes the row
CREATE OR REPLACE FUNCTION provision_cleanup() RETURNS TRIGGER AS $$
DECLARE
    v_status      RECORD;
    v_oi_plan_id   UUID;
BEGIN

    SELECT * INTO v_status FROM provision_status WHERE id = NEW.status_id;

    IF NOT v_status.is_final THEN
        RETURN NEW;
    END IF;

    IF NOT v_status.is_success THEN
        EXECUTE FORMAT('DELETE FROM %s WHERE id=$1',TG_RELNAME) USING NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_status_update()
-- description: called instead of update on v_provision_domain view and sets the status
CREATE OR REPLACE FUNCTION provision_status_update() RETURNS TRIGGER AS $$
BEGIN

    EXECUTE
        FORMAT('UPDATE %s SET status_id=$1 WHERE id=$2', NEW.reference_table)
        USING NEW.status_id, NEW.id;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;


-- function: provision_order_status_notify()
-- description: Notify about an provision order status
CREATE OR REPLACE FUNCTION provision_order_status_notify() RETURNS TRIGGER AS $$
DECLARE
    _order_id      UUID;
BEGIN
    _order_id = (NEW.order_metadata->>'order_id')::UUID;
    PERFORM notify_order_status(_order_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
