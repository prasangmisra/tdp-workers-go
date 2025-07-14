-- f_order_item_plan: simulates parameterized view
-- gets all order_item_plan records in hierarchical structure for given order item
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


-- f_order_item_plan_status: simulates parameterized view
-- gets a status summary for all order_item_plan records for a given order item
CREATE OR REPLACE FUNCTION f_order_item_plan_status(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                UUID,
                     order_item_id           UUID,
                     provision_order         INT,
                     total                   BIGINT,
                     total_new               BIGINT,
                     total_validated         BIGINT,
                     total_success           BIGINT,
                     total_fail              BIGINT,
                     total_processing        BIGINT,
                     objects                 TEXT[],
                     object_ids              UUID[],
                     order_item_plan_ids     UUID[]
                 )
AS $$
BEGIN
    RETURN QUERY
        SELECT
            p.order_id,
            p.order_item_id,
            p.provision_order,
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE p.plan_status_name='new') AS total_new,
            COUNT(*) FILTER (WHERE p.plan_validation_status_name='completed') AS total_validated,
            COUNT(*) FILTER (WHERE p.plan_status_is_success AND p.plan_status_is_final) AS total_success,
            COUNT(*) FILTER (WHERE NOT p.plan_status_is_success AND p.plan_status_is_final ) AS total_fail,
            COUNT(*) FILTER (WHERE p.plan_status_name='processing' ) AS total_processing,
            ARRAY_AGG(p.object_name) AS objects,
            ARRAY_AGG(p.object_id) AS object_ids,
            ARRAY_AGG(p.id) AS order_item_plan_ids
        FROM f_order_item_plan(p_order_item_id) p
        GROUP BY 1,2,3;
END;
$$ LANGUAGE plpgsql;


-- function: build_order_notification_payload()
-- description: grab all plan and order data for given order id
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
                                'error', p.result_message
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


-- function: notify_order_status()
-- description: Notify about an order status
CREATE OR REPLACE FUNCTION notify_order_status(_order_id UUID) RETURNS BOOLEAN AS $$
DECLARE
    _payload      JSONB;
BEGIN
    _payload = build_order_notification_payload(_order_id);
    PERFORM notify_event('order_notify','order_event_notify',_payload::TEXT);
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- function: order_next_status(order_id UUID, success BOOLEAN)
-- description: this function calculates the next suitable status
-- based on the order_status_path table and returns it.
-- it is to be used on an update of the "order" table.
CREATE OR REPLACE FUNCTION order_next_status(_order_id UUID,_is_success BOOLEAN) RETURNS UUID AS $$
DECLARE
    _status_transition RECORD;
    _current_status    UUID;
BEGIN

    SELECT t.* INTO _status_transition
    FROM v_order_status_transition t
             JOIN "order" o ON o.id = _order_id AND o.status_id = t.source_status_id
    WHERE
        t.path_id = o.path_id
            AND (_is_success AND t.is_target_success) OR (NOT _is_success AND NOT t.is_target_success);

    IF NOT FOUND THEN
        SELECT status_id INTO _current_status FROM "order" WHERE id=_order_id;
        RAISE NOTICE 'no suitable target status found, keeping same';
        RETURN _current_status;
    END IF;

    RETURN _status_transition.target_status_id;

END;
$$ LANGUAGE PLPGSQL;
