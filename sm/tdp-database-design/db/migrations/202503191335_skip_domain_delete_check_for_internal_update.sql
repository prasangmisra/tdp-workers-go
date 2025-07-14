-- function: order_prevent_if_domain_is_deleted()
-- description: check if the domain on the order data is deleted
CREATE OR REPLACE FUNCTION order_prevent_if_domain_is_deleted() RETURNS TRIGGER AS $$
BEGIN
    -- Skip the check if order type is update_internal
    PERFORM TRUE FROM v_order WHERE order_id = NEW.order_id AND product_name = 'domain' AND order_type_name = 'update_internal';

    IF FOUND THEN
        RETURN NEW;
    END IF;

    PERFORM TRUE FROM v_domain WHERE name=NEW.name and rgp_epp_status IN ('redemptionPeriod', 'pendingDelete');

    IF FOUND THEN
        RAISE EXCEPTION 'Domain ''%'' is deleted domain', NEW.name USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
