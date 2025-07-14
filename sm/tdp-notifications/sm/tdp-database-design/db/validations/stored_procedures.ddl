CREATE OR REPLACE FUNCTION check_order_type_for_product() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.product_id IS NOT NULL AND NEW.order_type_id IS NOT NULL THEN
        PERFORM 1
        FROM order_type
        WHERE id = NEW.order_type_id AND product_id = NEW.product_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order type % does not exist for product %', NEW.order_type_id, NEW.product_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;