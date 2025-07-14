DROP view if exists v_order_item_plan_status;
DROP VIEW IF EXISTS v_order_item_plan;


DROP VIEW IF EXISTS v_order_item_plan;
CREATE OR REPLACE VIEW v_order_item_plan AS
WITH RECURSIVE plan AS NOT MATERIALIZED (
    SELECT
        order_item_plan.*,
        NULL::uuid   AS parent_object_id,
        0            AS depth
    FROM order_item_plan
    WHERE order_item_plan.parent_id IS NULL
    union
    SELECT
        order_item_plan.*,
        plan.order_item_object_id as parent_object_id,
        plan.depth + 1
    FROM order_item_plan
             INNER JOIN plan on order_item_plan.parent_id = plan.id
)
SELECT oi.id         AS order_id,
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
       p.depth,
       p.parent_object_id

FROM plan p
         JOIN order_item_object obj ON obj.id = p.order_item_object_id
         JOIN order_item_plan_status s ON s.id = p.status_id
         JOIN order_item oi ON oi.id = p.order_item_id
         JOIN "order" o ON o.id = oi.order_id
         JOIN order_type t ON t.id = o.type_id
         JOIN product prod ON prod.id = t.product_id

ORDER BY p.depth DESC;

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

