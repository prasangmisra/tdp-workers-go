-- function: order_prevent_if_host_exists()
-- description: prevent create host if already exists
CREATE OR REPLACE FUNCTION order_prevent_if_host_exists() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE
    FROM only host h
             JOIN order_host oh
                  ON oh.name = h.name AND oh.tenant_customer_id = h.tenant_customer_id
    WHERE oh.id = NEW.host_id;

    IF FOUND THEN
        RAISE EXCEPTION 'already exists' USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_host_does_not_exist()
-- description: check if host from order data exists
CREATE OR REPLACE FUNCTION order_prevent_if_host_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    v_host RECORD;
BEGIN
    SELECT h.id, h.name INTO v_host
    FROM ONLY host h
             JOIN "order" o ON o.id=NEW.order_id
    WHERE (h.id = NEW.host_id OR h.name = NEW.host_name) AND h.tenant_customer_id = o.tenant_customer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Host ''% %'' not found', NEW.host_id, NEW.host_name USING ERRCODE = 'no_data_found';
    END IF;

    NEW.host_id = v_host.id;
    NEW.host_name = v_host.name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_host_in_use()
-- description: check if host is associated with any domain
CREATE OR REPLACE FUNCTION order_prevent_host_in_use() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM ONLY domain_host WHERE host_id = NEW.host_id;

    IF FOUND THEN
        RAISE EXCEPTION 'cannot delete host: in use.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
