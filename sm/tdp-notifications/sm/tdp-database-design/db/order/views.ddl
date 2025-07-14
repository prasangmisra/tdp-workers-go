CREATE OR REPLACE VIEW v_order_type AS 
SELECT 
    p.id AS product_id,
    p.name AS product_name,
    ot.id AS id,
    ot.name AS name
FROM product p 
    JOIN order_type ot ON ot.product_id=p.id
;




CREATE OR REPLACE VIEW v_order_status_transition AS
SELECT
  ost.path_id,
  osp.name AS path_name,
  f.id AS source_status_id,
  t.id AS target_status_id,
  f.name AS from_status,
  t.name AS to_status,
  f.is_success AS is_source_success,
  t.is_success AS is_target_success,
  t.is_final   AS is_final
  FROM order_status_transition ost
    JOIN order_status_path osp ON osp.id = ost.path_id
    JOIN order_status f ON f.id=ost.from_id
    JOIN order_status t ON t.id=ost.to_id
;


CREATE OR REPLACE VIEW v_order_product_type AS
  SELECT
    p.id AS product_id,
    p.name AS product_name,
    t.id   AS type_id,
    t.name AS type_name,
    FORMAT('order_item_%s_%s',t.name,p.name)::TEXT AS rel_name
  FROM product p
    JOIN order_type t ON t.product_id  = p.id
  ORDER BY 2,4
;

CREATE OR REPLACE VIEW v_order_item_plan_object AS 
SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_contact.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM create_domain_contact
    WHERE create_domain_id = d.id
  ) AS distinct_order_contact ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_host.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
  JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM create_domain_nameserver
    WHERE create_domain_id = d.id
  ) AS distinct_order_host ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_renew_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id AS object_id,
  d.id AS id
FROM order_item_redeem_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj on obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_delete_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_transfer_in_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_transfer_away_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_host.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
  JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM update_domain_add_nameserver
    WHERE update_domain_id = d.id
  ) AS distinct_order_host ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_contact.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM update_domain_contact
    WHERE update_domain_id = d.id

    UNION ALL

    SELECT DISTINCT order_contact_id AS id
    FROM update_domain_add_contact
    WHERE update_domain_id = d.id
    ) AS distinct_order_contact ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting_certificate'

UNION


SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_delete_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_update_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_create_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_update_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_delete_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_update_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_delete_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
;

CREATE OR REPLACE VIEW v_domain_order_item AS
SELECT
    oicd.id AS order_item_id,
    oicd.order_id,
    oicd.name AS domain_name,
    oicd.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_create_domain oicd
        JOIN order_item_status ois ON oicd.status_id = ois.id
        JOIN "order" o ON o.id = oicd.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oiud.id AS order_item_id,
    oiud.order_id,
    oiud.name AS domain_name,
    oiud.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_update_domain oiud
        JOIN order_item_status ois ON oiud.status_id = ois.id
        JOIN "order" o ON o.id = oiud.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oird.id AS order_item_id,
    oird.order_id,
    oird.name AS domain_name,
    oird.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_redeem_domain oird
        JOIN order_item_status ois ON oird.status_id = ois.id
        JOIN "order" o ON o.id = oird.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oidd.id AS order_item_id,
    oidd.order_id,
    oidd.name AS domain_name,
    oidd.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_delete_domain oidd
        JOIN order_item_status ois ON oidd.status_id = ois.id
        JOIN "order" o ON o.id = oidd.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oird.id AS order_item_id,
    oird.order_id,
    oird.name AS domain_name,
    oird.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_renew_domain oird
        JOIN order_item_status ois ON oird.status_id = ois.id
        JOIN "order" o ON o.id = oird.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oitid.id AS order_item_id,
    oitid.order_id,
    oitid.name AS domain_name,
    oitid.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_transfer_in_domain oitid
        JOIN order_item_status ois ON oitid.status_id = ois.id
        JOIN "order" o ON o.id = oitid.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id

UNION ALL

SELECT
    oitad.id AS order_item_id,
    oitad.order_id,
    oitad.name AS domain_name,
    oitad.status_id,
    ois.name AS order_item_status,
    ois.id AS order_item_status_id,
    os.name AS order_status,
    os.id AS order_status_id,
    os.is_final AS order_status_is_final,
    os.is_success AS order_status_is_success,
    ot.name AS order_type,
    o.tenant_customer_id
FROM
    order_item_transfer_away_domain oitad
        JOIN order_item_status ois ON oitad.status_id = ois.id
        JOIN "order" o ON o.id = oitad.order_id
        JOIN order_status os ON os.id = o.status_id
        JOIN order_type ot ON ot.id = o.type_id
;

-- can select domain name from this view where status is not final?
-- updates and delete may happen by id however. should we get the domain name first using id and
-- then do the check?
CREATE OR REPLACE VIEW v_hosting_order_item AS

SELECT
    oich.id AS order_item_id,
    oich.order_id,
    oich.domain_name,
    os.is_final AS order_status_is_final
FROM
  order_item_create_hosting oich
    JOIN "order" o ON o.id = oich.order_id
    JOIN order_status os ON os.id = o.status_id

UNION ALL

SELECT
  oiuh.id AS order_item_id,
  oiuh.order_id,
  h.domain_name,
  os.is_final AS order_status_is_final
FROM
  order_item_update_hosting oiuh
    JOIN "order" o ON o.id = oiuh.order_id
    JOIN order_status os ON os.id = o.status_id
    JOIN hosting h on h.id = oiuh.hosting_id

UNION ALL

SELECT
  oidh.id AS order_item_id,
  oidh.order_id,
  h.domain_name,
  os.is_final AS order_status_is_final
FROM 
  order_item_delete_hosting oidh
    JOIN "order" o ON o.id = oidh.order_id
    JOIN order_status os ON os.id = o.status_id
    JOIN hosting h on h.id = oidh.hosting_id
;