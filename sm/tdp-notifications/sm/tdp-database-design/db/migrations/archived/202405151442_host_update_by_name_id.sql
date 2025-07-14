-- add host_name identifier to allow for host update by name 
ALTER TABLE IF EXISTS order_item_update_host ADD COLUMN IF NOT EXISTS host_name FQDN NOT NULL;

-- function: order_prevent_if_host_does_not_exist()
-- description: check if host from order data exists
CREATE OR REPLACE FUNCTION order_prevent_if_host_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    v_host RECORD;
BEGIN

    SELECT id, name INTO v_host 
    FROM ONLY host
    WHERE id = NEW.host_id OR name = NEW.host_name;

    IF NOT FOUND THEN 
        RAISE EXCEPTION 'Host ''% %'' not found', NEW.host_id, NEW.host_name USING ERRCODE = 'no_data_found';
    END IF;

    NEW.host_id = v_host.id;
    NEW.host_name = v_host.name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;