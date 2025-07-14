-- function: order_prevent_if_host_does_not_exist()
-- description: check if host from order data exists
CREATE OR REPLACE FUNCTION order_prevent_if_host_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    v_host RECORD;
BEGIN
    SELECT h.id, h.name INTO v_host
    FROM ONLY host h
    JOIN "order" o ON o.id=NEW.order_id
    WHERE h.id = NEW.host_id OR (h.name = NEW.host_name AND h.tenant_customer_id = o.tenant_customer_id);

    IF NOT FOUND THEN 
        RAISE EXCEPTION 'Host ''% %'' not found', NEW.host_id, NEW.host_name USING ERRCODE = 'no_data_found';
    END IF;

    NEW.host_id = v_host.id;
    NEW.host_name = v_host.name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
