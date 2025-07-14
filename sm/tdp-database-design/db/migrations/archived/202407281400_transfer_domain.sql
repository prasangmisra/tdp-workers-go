-------------------------------- 202407281400_transfer_domain.sql ------------------------------------

-- Add new order type for transfer domain
DELETE FROM order_type WHERE name = 'transfer';
INSERT INTO order_type (product_id,name) SELECT id, 'transfer_in' FROM product WHERE name = 'domain' ON CONFLICT DO NOTHING;

-- new order item strategy for transfer domain order
INSERT INTO order_item_strategy(order_type_id,object_id,provision_order) VALUES
(
    (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_in'),
    tc_id_from_name('order_item_object','domain'),
    1
)
ON CONFLICT DO NOTHING;

-- Insert new attribute keys
INSERT INTO attr_key(
  name,
  category_id,
  descr,
  value_type_id,
  default_value,
  allow_null
) VALUES
(
  'allowed_transfer_periods',
  (SELECT id FROM attr_category WHERE name='lifecycle'),
  'List of allowed transfer periods',
  (SELECT id FROM attr_value_type WHERE name='INTEGER_LIST'),
  '{1}'::TEXT,
  FALSE
),
(
  'is_transfer_allowed',
  (SELECT id FROM attr_category WHERE name='order'),
  'Registry supports domain transfer',
  (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'authcode_mandatory_for_orders',
  (SELECT id FROM attr_category WHERE name='order'),
  'List of order types which require authcode',
  (SELECT id FROM attr_value_type WHERE name='TEXT_LIST'),
  '{}'::TEXT,
  FALSE
) ON CONFLICT DO NOTHING;


-- Add unique constraint to attr_value
ALTER TABLE IF EXISTS attr_value DROP CONSTRAINT IF EXISTS attr_value_key_id_tld_id_key;
CREATE UNIQUE INDEX ON attr_value(key_id,tld_id,tenant_id);

----------------------------------------------- Tables -----------------------------------------------

--
-- table: order_item_transfer_in_domain
-- description: this table stores attributes of domain transfer orders.
--

CREATE TABLE order_item_transfer_in_domain (
  name                  FQDN NOT NULL,
  accreditation_tld_id  UUID NOT NULL REFERENCES accreditation_tld,
  transfer_period       INT NOT NULL DEFAULT 1,
  auth_info             TEXT,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

DROP VIEW IF EXISTS v_order_transfer_in_domain;
CREATE OR REPLACE VIEW v_order_transfer_in_domain AS 
SELECT
  tid.id AS order_item_id,
  tid.order_id AS order_id,
  tid.accreditation_tld_id,
  o.metadata AS order_metadata,
  o.tenant_customer_id,
  o.type_id,
  o.customer_user_id,
  o.status_id,
  s.name AS status_name,
  s.descr AS status_descr,
  s.is_final AS status_is_final,
  tc.tenant_id,
  tc.customer_id,
  tc.tenant_name,
  tc.name,
  at.provider_name,
  at.provider_instance_id,
  at.provider_instance_name,
  at.tld_id AS tld_id,
  at.tld_name AS tld_name,
  at.accreditation_id,
  tid.name AS domain_name,
  tid.transfer_period,
  tid.auth_info
FROM order_item_transfer_in_domain tid
  JOIN "order" o ON o.id=tid.order_id
  JOIN v_order_type ot ON ot.id = o.type_id
  JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
  JOIN order_status s ON s.id = o.status_id
  JOIN v_accreditation_tld at ON at.accreditation_tld_id = tid.accreditation_tld_id
;

----------------------------------------------- Functions --------------------------------------------

--
-- function: order_prevent_multiple_processing_transfers
-- description: prevents multiple processing transfers
-- 
CREATE OR REPLACE FUNCTION order_prevent_multiple_processing_transfers() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM v_order_transfer_in_domain
    WHERE order_item_id != NEW.id AND domain_name = NEW.name AND (NOT status_is_final);

    IF FOUND THEN
      RAISE EXCEPTION 'Domain ''%'' has active transfers', NEW.name USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- function: order_prevent_if_domain_transfer_unsupported()
-- description: prevents domain transfer if tld not support transfer domains
--
CREATE OR REPLACE FUNCTION order_prevent_if_domain_transfer_unsupported() RETURNS TRIGGER AS $$
DECLARE
  v_is_transfer_allowed  BOOLEAN;
BEGIN
  SELECT get_tld_setting(
    p_key=>'tld.order.is_transfer_allowed',
    p_accreditation_tld_id=>NEW.accreditation_tld_id
  )
  INTO v_is_transfer_allowed;

  IF NOT v_is_transfer_allowed THEN
    RAISE EXCEPTION 'TLD ''%'' does not support domain transfer', tld_part(NEW.name);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 
-- function: validate_period()
-- description: validates the period of the order item
--
CREATE OR REPLACE FUNCTION validate_period() RETURNS TRIGGER AS $$
DECLARE
    allowed_periods INT[];
    period_to_validate INT;
    period_key TEXT;
    validation_type TEXT;
BEGIN
    -- Determine which period to validate based on the trigger argument
    validation_type := TG_ARGV[0];

    IF validation_type = 'registration' THEN
        period_to_validate := NEW.registration_period;
        period_key := 'tld.lifecycle.allowed_registration_periods';
    ELSIF validation_type = 'renewal' THEN
        period_to_validate := NEW.period;
        period_key := 'tld.lifecycle.allowed_renewal_periods';
    ELSIF validation_type = 'transfer_in' THEN
        period_to_validate := NEW.transfer_period;
        period_key := 'tld.lifecycle.allowed_transfer_periods';
    ELSE
        RAISE EXCEPTION 'Invalid validation type: %', validation_type;
    END IF;

    SELECT get_tld_setting(
        p_key => period_key,
        p_accreditation_tld_id => NEW.accreditation_tld_id
    ) INTO allowed_periods;

    -- Check if the period is within the allowed range
    IF NOT (period_to_validate = ANY(allowed_periods)) THEN
        RAISE EXCEPTION '% period must be one of the allowed values: %',
            validation_type, array_to_string(allowed_periods, ', ');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- function: validate_auth_info()
-- description: validates the auth info for a specific order type
--
CREATE OR REPLACE FUNCTION validate_auth_info() RETURNS TRIGGER AS $$
DECLARE
  order_type                       TEXT;
  v_authcode_mandatory_for_orders  TEXT[];
BEGIN
  -- Determine which order type to validate based on the trigger argument
  order_type := TG_ARGV[0];

  -- Get order types that require auth info
  SELECT get_tld_setting(
    p_key => 'tld.order.authcode_mandatory_for_orders',
    p_accreditation_tld_id => NEW.accreditation_tld_id
  ) INTO v_authcode_mandatory_for_orders;

  -- Check if the auth info is mandatory for the order type
  IF order_type = ANY(v_authcode_mandatory_for_orders) AND (NEW.auth_info IS NULL OR NEW.auth_info = '') THEN
    RAISE EXCEPTION 'Auth info is mandatory for ''%'' order', order_type;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------- Triggers ---------------------------------------------

-- prevents multiple processing transfer orders for the same domain name
CREATE TRIGGER order_prevent_multiple_processing_transfers_tg
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW EXECUTE PROCEDURE order_prevent_multiple_processing_transfers();

-- make sure the initial status is 'pending'
CREATE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- sets the TLD_ID on when the it does not contain one
CREATE TRIGGER order_item_set_tld_id_tg 
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW WHEN ( NEW.accreditation_tld_id IS NULL )
  EXECUTE PROCEDURE order_item_set_tld_id();

-- prevents order creation if domain transfer is unsupported
CREATE TRIGGER order_prevent_if_domain_transfer_unsupported_tg
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_transfer_unsupported();

-- make sure the transfer period is valid
CREATE TRIGGER validate_period_tg
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW EXECUTE PROCEDURE validate_period('transfer_in');

-- make sure the transfer auth info is valid
CREATE TRIGGER validate_auth_info_tg
  BEFORE INSERT ON order_item_transfer_in_domain
  FOR EACH ROW EXECUTE PROCEDURE validate_auth_info('transfer_in');

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_create_plan_tg
  AFTER UPDATE ON order_item_transfer_in_domain 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE plan_order_item();

-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_transfer_in_domain 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_transfer_in_domain
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_transfer_in_domain(order_id);
CREATE INDEX ON order_item_transfer_in_domain(status_id);
