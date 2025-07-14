--
-- function: order_prevent_if_domain_does_not_exist()
-- description: check if domain from order data exists
--

CREATE OR REPLACE FUNCTION order_prevent_if_domain_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    v_domain    RECORD;
BEGIN
  SELECT * INTO v_domain
  FROM domain d
  JOIN "order" o ON o.id=NEW.order_id
  WHERE d.name=NEW.name OR d.id=NEW.domain_id
    AND d.tenant_customer_id=o.tenant_customer_id;

  IF NOT FOUND THEN
        RAISE EXCEPTION 'Domain ''% %'' not found', NEW.domain_id, NEW.name USING ERRCODE = 'no_data_found';
  END IF;

  NEW.domain_id = v_domain.id;
  NEW.name = v_domain.name;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;