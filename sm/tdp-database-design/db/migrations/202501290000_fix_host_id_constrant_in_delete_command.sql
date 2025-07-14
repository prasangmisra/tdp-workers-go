-- Update order_item_update_host table
ALTER TABLE IF EXISTS  order_item_update_host
    DROP CONSTRAINT IF EXISTS order_item_update_host_host_id_fkey,
    DROP CONSTRAINT IF EXISTS order_item_update_host_new_host_id_fkey,
    ADD CONSTRAINT order_item_update_host_new_host_id_fkey FOREIGN KEY (new_host_id) REFERENCES order_host;