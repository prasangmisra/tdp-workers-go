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

-- insert explicit_renew_supported & allowed_renew_periods attribute
DO $$
    DECLARE
        category_id UUID;
        boolean_type_id UUID;
        integerlist_type_id UUID;
    BEGIN
        SELECT id INTO category_id FROM attr_category WHERE name = 'lifecycle';
        SELECT id INTO boolean_type_id FROM attr_value_type WHERE name = 'BOOLEAN';
        SELECT id INTO integerlist_type_id FROM attr_value_type WHERE name = 'INTEGER_LIST';

        INSERT INTO attr_key (name, category_id, descr, value_type_id, default_value, allow_null)
        VALUES
            ('explicit_renew_supported', category_id, 'Registry supports domain explicit renew', boolean_type_id, TRUE, FALSE),
            ('allowed_renew_periods', category_id, 'Registry allowed renewal periods', integerlist_type_id, '{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}', FALSE)
        ON CONFLICT DO NOTHING;
END $$;

--
-- function: order_prevent_if_renew_unsupported()
-- description: prevents domain renew if tld not support renew domains
--

CREATE OR REPLACE FUNCTION order_prevent_if_renew_unsupported() RETURNS TRIGGER AS $$
DECLARE
  v_explicit_renew_supported  BOOLEAN;
  v_allowed_renew_periods      INT[];
BEGIN

  SELECT value INTO v_explicit_renew_supported
  FROM v_attribute va
  JOIN domain d ON d.name = NEW.name
  JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
  WHERE va.key = 'tld.lifecycle.explicit_renew_supported' AND va.tld_name = vat.tld_name;

  IF NOT v_explicit_renew_supported THEN
      RAISE EXCEPTION 'Explicit domain renew is not allowed';
  END IF;

  SELECT value INTO v_allowed_renew_periods
  FROM v_attribute va
  JOIN domain d ON d.name = NEW.name
  JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
  WHERE va.key = 'tld.lifecycle.allowed_renew_periods' AND va.tld_name = vat.tld_name;

  IF NOT (NEW.period = ANY(v_allowed_renew_periods)) THEN
      RAISE EXCEPTION 'Period ''%'' is invalid renew period', NEW.period;
  END IF;

  RETURN NEW;

END;
$$ LANGUAGE plpgsql;

-- drop old trigger
DROP TRIGGER IF EXISTS aa_order_prevent_if_domain_does_not_exist_tg ON order_item_renew_domain;

-- check if domain from order data exists
CREATE TRIGGER aa_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_renew_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();


-- drop old trigger
DROP TRIGGER IF EXISTS order_prevent_if_renew_unsupported_tg ON order_item_renew_domain;

-- prevent renew domain if tld not support renew
CREATE TRIGGER order_prevent_if_renew_unsupported_tg
    BEFORE INSERT ON order_item_renew_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_renew_unsupported();
