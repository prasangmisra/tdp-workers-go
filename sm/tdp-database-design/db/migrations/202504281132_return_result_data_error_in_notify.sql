CREATE OR REPLACE FUNCTION job_parent_status_update() RETURNS TRIGGER AS $$
DECLARE
    _job_status            RECORD;
    _parent_job            RECORD;
BEGIN

    -- no parent; nothing to do
    IF NEW.parent_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT * INTO _job_status FROM job_status WHERE id = NEW.status_id;

    -- child job not final; nothing to do
    IF NOT _job_status.is_final THEN
        RETURN NEW;
    END IF;

    -- parent has final status; nothing to do
    SELECT * INTO _parent_job FROM v_job WHERE job_id = NEW.parent_id;
    IF _parent_job.job_status_is_final THEN
        RETURN NEW;
    END IF;

    -- child job failed hard; fail parent
    IF NOT _job_status.is_success AND NEW.is_hard_fail THEN
        UPDATE job
        SET
            status_id = tc_id_from_name('job_status', 'failed'),
            result_message = NEW.result_message,
            result_data = NEW.result_data
        WHERE id = NEW.parent_id;
        RETURN NEW;
    END IF;

    -- check for unfinished children jobs
    PERFORM TRUE FROM v_job WHERE job_parent_id = NEW.parent_id AND NOT job_status_is_final;

    IF NOT FOUND THEN

        PERFORM TRUE FROM v_job WHERE job_parent_id = NEW.parent_id AND job_status_is_success;

        IF FOUND THEN
            UPDATE job SET status_id = tc_id_from_name('job_status', 'submitted') WHERE id = NEW.parent_id;
        ELSE
            -- all children jobs had failed
            UPDATE job
            SET
                status_id = tc_id_from_name('job_status', 'failed'),
                result_message = NEW.result_message,
                result_data = NEW.result_data
            WHERE id = NEW.parent_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP FUNCTION IF EXISTS f_order_item_plan(p_order_item_id UUID);
CREATE OR REPLACE FUNCTION f_order_item_plan(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                       UUID,
                     id                             UUID,
                     parent_id                      UUID,
                     order_item_id                  UUID,
                     plan_status_id                 UUID,
                     object_id                      UUID,
                     plan_status_name               TEXT,
                     plan_status_is_success         BOOLEAN,
                     plan_status_is_final           BOOLEAN,
                     plan_validation_status_name    TEXT,
                     object_name                    TEXT,
                     reference_id                   UUID,
                     result_message                 TEXT,
                     result_data                    JSONB,
                     provision_order                INT,
                     parent_object_id               UUID
                 )
AS $$
BEGIN
    RETURN QUERY
        WITH RECURSIVE plan AS (
            SELECT
                order_item_plan.*,
                NULL::uuid   AS parent_object_id
            FROM order_item_plan
            WHERE order_item_plan.parent_id IS NULL AND order_item_plan.order_item_id = p_order_item_id
            UNION ALL  -- Using UNION ALL since duplicates are impossible
            SELECT
                order_item_plan.*,
                plan.order_item_object_id as parent_object_id
            FROM order_item_plan
                     INNER JOIN plan on order_item_plan.parent_id = plan.id
            WHERE order_item_plan.order_item_id = p_order_item_id
        )
        SELECT
            oi.order_id AS order_id,
            p.id AS id,
            p.parent_id AS parent_id,
            p.order_item_id AS order_item_id,
            s.id AS plan_status_id,
            obj.id AS object_id,
            s.name AS plan_status_name,
            s.is_success AS plan_status_is_success,
            s.is_final AS plan_status_is_final,
            vs.name AS plan_validation_status_name,
            obj.name AS object_name,
            p.reference_id AS reference_id,
            p.result_message,
            p.result_data,
            p.provision_order,
            p.parent_object_id
        FROM plan p
                 JOIN order_item_object obj ON obj.id = p.order_item_object_id
                 JOIN order_item_plan_status s ON s.id = p.status_id
                 JOIN order_item_plan_validation_status vs ON vs.id = p.validation_status_id
                 JOIN order_item oi ON oi.id = p.order_item_id
        ORDER BY p.provision_order ASC;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION f_order_item_plan(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                       UUID,
                     id                             UUID,
                     parent_id                      UUID,
                     order_item_id                  UUID,
                     plan_status_id                 UUID,
                     object_id                      UUID,
                     plan_status_name               TEXT,
                     plan_status_is_success         BOOLEAN,
                     plan_status_is_final           BOOLEAN,
                     plan_validation_status_name    TEXT,
                     object_name                    TEXT,
                     reference_id                   UUID,
                     result_message                 TEXT,
                     result_data                    JSONB,
                     provision_order                INT,
                     parent_object_id               UUID
                 )
AS $$
BEGIN
    RETURN QUERY
        WITH RECURSIVE plan AS (
            SELECT
                order_item_plan.*,
                NULL::uuid   AS parent_object_id
            FROM order_item_plan
            WHERE order_item_plan.parent_id IS NULL AND order_item_plan.order_item_id = p_order_item_id
            UNION ALL  -- Using UNION ALL since duplicates are impossible
            SELECT
                order_item_plan.*,
                plan.order_item_object_id as parent_object_id
            FROM order_item_plan
                     INNER JOIN plan on order_item_plan.parent_id = plan.id
            WHERE order_item_plan.order_item_id = p_order_item_id
        )
        SELECT
            oi.order_id AS order_id,
            p.id AS id,
            p.parent_id AS parent_id,
            p.order_item_id AS order_item_id,
            s.id AS plan_status_id,
            obj.id AS object_id,
            s.name AS plan_status_name,
            s.is_success AS plan_status_is_success,
            s.is_final AS plan_status_is_final,
            vs.name AS plan_validation_status_name,
            obj.name AS object_name,
            p.reference_id AS reference_id,
            p.result_message,
            p.result_data,
            p.provision_order,
            p.parent_object_id
        FROM plan p
                 JOIN order_item_object obj ON obj.id = p.order_item_object_id
                 JOIN order_item_plan_status s ON s.id = p.status_id
                 JOIN order_item_plan_validation_status vs ON vs.id = p.validation_status_id
                 JOIN order_item oi ON oi.id = p.order_item_id
        ORDER BY p.provision_order ASC;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION build_order_notification_payload(_order_id UUID) RETURNS JSONB AS $$
DECLARE
    _payload      JSONB;
BEGIN
    SELECT
        JSONB_BUILD_OBJECT(
                'order_id', oi.order_id,
                'order_status_name', vo.order_status_name,
                'order_item_plans', JSON_AGG(
                        JSONB_BUILD_OBJECT(
                                'object', p.object_name,
                                'status', p.plan_status_name,
                                'error', p.result_message,
                                'error_details', p.result_data->'error'
                        )
                                    )
        )
    INTO _payload
    FROM order_item oi
             JOIN f_order_item_plan(oi.id) p ON TRUE
             JOIN v_order vo ON vo.order_id = oi.order_id
    WHERE oi.order_id = _order_id
    GROUP BY oi.order_id, vo.order_status_name;

    RETURN _payload;
END;
$$ LANGUAGE plpgsql;
