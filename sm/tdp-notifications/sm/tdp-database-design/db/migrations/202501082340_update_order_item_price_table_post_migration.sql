-- Drop the order_id column
ALTER TABLE IF EXISTS order_item_price
DROP COLUMN IF EXISTS order_id;
