-- Step 1: Create a new view to replace the old one
DROP VIEW IF EXISTS v_order_item_price;
CREATE OR REPLACE VIEW v_order_item_price AS
SELECT
  oip.order_item_id,
  oip.price,
  o.id AS order_id,
  o.tenant_customer_id,
  c.id AS currency_type_id,
  c.name AS currency_type_code,
  c.descr AS currency_type_descr,
  c.fraction AS currency_type_fraction,
  p.name AS product_name,
  ot.name AS order_type_name
FROM order_item_price oip
JOIN currency_type c ON c.id = oip.currency_type_id
JOIN order_item oi ON oi.id = oip.order_item_id
JOIN "order" o ON o.id = oi.order_id
JOIN order_type ot ON ot.id = o.type_id 
JOIN product p ON p.id=ot.product_id;

-- Step 2: Drop the foreign key constraint
ALTER TABLE IF EXISTS order_item_price
DROP CONSTRAINT IF EXISTS order_item_price_order_id_fkey;

-- Step 3: Drop the NOT NULL constraint on order_id
ALTER TABLE IF EXISTS order_item_price
ALTER COLUMN order_id DROP NOT NULL;

-- Step 4: Set order_id to NULL
UPDATE order_item_price
SET order_id = NULL;
