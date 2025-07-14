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


-- prevent create host if already exists 
CREATE OR REPLACE TRIGGER order_prevent_if_host_exists_tg
  BEFORE INSERT ON order_item_create_host
  FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_host_exists();
