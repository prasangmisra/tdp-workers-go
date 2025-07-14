------------------------------------------------------------202407291945_rename_order_price_table.sql------------------------------------------------------------ 
ALTER TABLE order_price RENAME TO order_item_price;


DROP VIEW IF EXISTS v_order_item_price;
CREATE OR REPLACE VIEW v_order_item_price AS
SELECT
    oip.order_item_id,
    oip.order_id,
    oip.price,
    c.id AS currency_id,
    c.name AS currency_code,
    c.descr AS currency_descr,
    c.fraction AS currency_fraction,
    o.tenant_customer_id,
    p.name AS product_name,
    ot.name AS order_type_name
FROM order_item_price oip
JOIN currency c ON c.id = oip.currency_id
JOIN "order" o ON o.id=oip.order_id
JOIN order_type ot ON ot.id = o.type_id 
JOIN product p ON p.id=ot.product_id
;
