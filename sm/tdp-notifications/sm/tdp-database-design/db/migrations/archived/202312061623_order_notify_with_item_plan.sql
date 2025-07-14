-- update result_msg to result_message matching order_item_plan
DO $$
BEGIN
  IF EXISTS(SELECT * FROM information_schema.columns  WHERE table_name='job' and column_name='result_msg')
  THEN ALTER TABLE job RENAME COLUMN result_msg TO result_message;
  END IF;
END $$;

-- update job view to reflect the change
DROP VIEW IF EXISTS v_job;
CREATE OR REPLACE VIEW v_job AS
SELECT
    j.id AS job_id,
    j.tenant_customer_id,
    js.name AS job_status_name,
    jt.name AS job_type_name,
    j.created_date,
    j.start_date,
    j.end_date,
    j.retry_date,
    j.retry_count,
    j.reference_id,
    jt.reference_table,
    j.result_message,
    j.result_data,
    j.data AS data,
    TO_JSONB(vtc.*) AS tenant_customer,
    jt.routing_key,
    js.is_final AS job_status_is_final,
    j.event_id
FROM job j
         JOIN job_status js ON j.status_id = js.id
         JOIN job_type jt ON jt.id = j.type_id
         JOIN v_tenant_customer vtc ON vtc.id = j.tenant_customer_id
;


-- create new notify funtion
CREATE OR REPLACE FUNCTION notify_order_status_transition_final_tfg() RETURNS TRIGGER AS
$$
DECLARE
_payload      JSONB;
BEGIN
WITH order_items AS (
    SELECT JSON_AGG(
                   JSONB_BUILD_OBJECT(
                           'object', object_name,
                           'status', plan_status_name,
                           'error', result_message
                   )
           ) AS data
    FROM v_order_item_plan
    WHERE order_id = OLD.id
)
SELECT
    JSONB_BUILD_OBJECT(
            'order_id', o.order_id,
            'order_status_name', o.order_status_name,
            'order_item_plans', order_items.data
    )
INTO _payload
FROM v_order o
         JOIN order_items ON TRUE
WHERE order_id =OLD.id;

PERFORM notify_event('order_notify','order_event_notify',_payload::TEXT);
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- drop old trigger
DROP TRIGGER order_status_transition_final_tg ON "order";

-- create trigger for notify funtion
CREATE TRIGGER order_status_transition_final_tg
AFTER UPDATE OF status_id ON "order"
FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id AND (NEW.status_id = tc_id_from_name('order_status', 'successful') OR NEW.status_id = tc_id_from_name('order_status', 'failed')))
EXECUTE PROCEDURE notify_order_status_transition_final_tfg();
COMMENT ON TRIGGER order_status_transition_final_tg ON "order" IS 'send a notification to the order manager service when an order is completed';

-- drop old funtion
DROP FUNCTION IF EXISTS nofify_order_status_transition_final_tfg();

-- drop v_order_item_plan_status that relies on v_order_item_plan
DROP VIEW IF EXISTS v_order_item_plan_status;
DROP VIEW IF EXISTS v_order_item_plan;

-- create updated v_order_item_plan
CREATE OR REPLACE VIEW v_order_item_plan AS
WITH RECURSIVE plan AS NOT MATERIALIZED (
  SELECT
    o.id AS order_id,
    p.id AS id,
    p.parent_id AS parent_id,
    t.id AS order_type_id,
    prod.id AS product_id,
    p.order_item_id AS order_item_id,
    s.id AS plan_status_id,
    obj.id AS object_id,
    prod.name AS product_name,
    t.name AS order_type_name,
    s.name AS plan_status_name,
    s.is_success AS plan_status_is_success,
    s.is_final AS plan_status_is_final,
    obj.name AS object_name,
    p.reference_id AS reference_id,
    p.result_message,
    NULL AS parent_object_name,
    0 AS depth
  FROM order_item_plan p
    JOIN order_item_object obj ON obj.id = p.order_item_object_id
    JOIN order_item_plan_status s ON s.id=p.status_id
    JOIN order_item oi ON oi.id = p.order_item_id
    JOIN "order" o ON o.id = oi.order_id
    JOIN order_type t ON t.id = o.type_id
    JOIN product prod ON prod.id = t.product_id
  WHERE p.parent_id IS NULL

  UNION

  SELECT
    o.id AS order_id,
    p.id AS id,
    p.parent_id AS parent_id,
    t.id AS order_type_id,
    prod.id AS product_id,
    p.order_item_id AS order_item_id,
    s.id AS plan_status_id,
    obj.id AS object_id,
    prod.name AS product_name,
    t.name AS order_type_name,
    s.name AS plan_status_name,
    s.is_success AS plan_status_is_success,
    s.is_final AS plan_status_is_final,
    obj.name AS object_name,
    p.reference_id AS reference_id,
    p.result_message,
    plan.object_name AS parent_object_name,
    depth + 1
  FROM order_item_plan p
    JOIN order_item_object obj ON obj.id = p.order_item_object_id
    JOIN order_item_plan_status s ON s.id=p.status_id
    JOIN order_item oi ON oi.id = p.order_item_id
    JOIN "order" o ON o.id = oi.order_id
    JOIN order_type t ON t.id = o.type_id
    JOIN product prod ON prod.id = t.product_id
    JOIN plan ON p.parent_id = plan.id
)
SELECT * FROM plan ORDER BY depth DESC;

-- recreate v_order_item_plan_status
CREATE OR REPLACE VIEW v_order_item_plan_status AS
SELECT
    order_id,
    order_item_id,
    depth,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE plan_status_name='new') AS total_new,
        COUNT(*) FILTER (WHERE plan_status_is_success AND plan_status_is_final) AS total_success,
        COUNT(*) FILTER (WHERE NOT plan_status_is_success AND plan_status_is_final ) AS total_fail,
        COUNT(*) FILTER (WHERE NOT plan_status_is_final AND plan_status_name != 'new' ) AS total_processing,
        ARRAY_AGG(object_name) AS objects,
    ARRAY_AGG(object_id) AS object_ids
FROM v_order_item_plan
GROUP BY 1,2,3
ORDER BY depth DESC;
