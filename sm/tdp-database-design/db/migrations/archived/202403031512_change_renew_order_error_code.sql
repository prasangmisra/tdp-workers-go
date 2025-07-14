-- function: validate_domain_renew_order()
-- description: validate domain renew order data
CREATE OR REPLACE FUNCTION validate_renew_order_domain_exists() RETURNS TRIGGER AS $$
DECLARE
  v_domain   RECORD;
  v_order    RECORD;
	curDate 	 date;
BEGIN
	curDate := DATE(NEW.current_expiry_date);

    SELECT * INTO v_order
    FROM "order"
    WHERE id=NEW.order_id;

    SELECT * INTO v_domain
    FROM domain
    WHERE name=NEW.name
    AND tenant_customer_id=v_order.tenant_customer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Domain ''%'' not found', NEW.name USING ERRCODE = 'no_data_found';
    END IF;

    IF curDate != DATE(v_domain.ry_expiry_date) THEN
        RAISE EXCEPTION 'Date ''%'' does not match current expiry date', curDate;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
