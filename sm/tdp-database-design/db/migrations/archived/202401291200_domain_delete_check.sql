-- add unique_attr_key_unique_name_and_category_id constraint 
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'unique_attr_key_unique_name_and_category_id' 
            AND table_name = 'attr_key'
    ) THEN
        ALTER TABLE attr_key
        ADD CONSTRAINT unique_attr_key_unique_name_and_category_id
        UNIQUE (name,category_id);
    END IF;
END $$;

-- remove typo explicate_delete_supported attr_key
DELETE FROM attr_key WHERE name = 'explicate_delete_supported';

-- insert explicit_delete_supported attribute
DO $$
    DECLARE
        category_id UUID;
        value_type_id UUID;
    BEGIN
        SELECT id INTO category_id FROM attr_category WHERE name = 'lifecycle';
        SELECT id INTO value_type_id FROM attr_value_type WHERE name = 'BOOLEAN';

        INSERT INTO attr_key (name, category_id, descr, value_type_id, default_value, allow_null)
        VALUES
            ('explicit_delete_supported', category_id, 'Registry supports domain explicit delete', value_type_id, TRUE, FALSE)
        ON CONFLICT DO NOTHING;
END $$;

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
    WHERE d.name=NEW.name
      AND d.tenant_customer_id=o.tenant_customer_id
      AND d.status_id = tc_id_from_name('domain_status', 'active');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Domain ''%'' not found', NEW.name USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- function: order_prevent_if_delete_unsupported()
-- description: prevents domain delete if tld not support delete domains
--

CREATE OR REPLACE FUNCTION order_prevent_if_delete_unsupported() RETURNS TRIGGER AS $$
DECLARE
  v_explicit_delete_supported  BOOLEAN;
BEGIN
  SELECT value INTO v_explicit_delete_supported
  FROM v_attribute va
  JOIN domain d ON d.name = NEW.name
  JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
  WHERE va.key = 'tld.lifecycle.explicit_delete_supported' AND va.tld_name = vat.tld_name;

  IF NOT v_explicit_delete_supported THEN
    RAISE EXCEPTION 'Explicit domain delete is not allowed';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- drop old trigger
DROP TRIGGER IF EXISTS aa_order_prevent_if_domain_does_not_exist_tg ON order_item_delete_domain;

-- check if domain from order data exists
CREATE TRIGGER aa_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_delete_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();


-- drop old trigger
DROP TRIGGER IF EXISTS order_prevent_if_delete_unsupported_tg ON order_item_delete_domain;

-- prevent delete domain if tld not support delete
CREATE TRIGGER order_prevent_if_delete_unsupported_tg
    BEFORE INSERT ON order_item_delete_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_delete_unsupported();
