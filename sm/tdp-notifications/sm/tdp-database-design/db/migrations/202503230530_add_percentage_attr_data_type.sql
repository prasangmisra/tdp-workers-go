-- function: is_percentage
-- description: Checks if the value is a valid percentage. Must be greater than or equal to 0.
CREATE OR REPLACE FUNCTION is_percentage(value NUMERIC) RETURNS BOOLEAN AS $$
BEGIN
  IF value < 0 THEN
    RAISE EXCEPTION 'Value must be greater than or equal to 0. Value: %', value;
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- Drop type PERCENTAGE if it exists.
DROP DOMAIN IF EXISTS PERCENTAGE;

-- type: PERCENTAGE
-- description: A percentage value, at most 10 digits with 2 decimal places.
CREATE DOMAIN PERCENTAGE AS NUMERIC(10, 2)
CHECK(
    -- The inserted value is always a percentage. at least 0%.
    is_percentage(value)
);


-- Add a new data type for attributes: PERCENTAGE.
INSERT INTO attr_value_type (name,data_type) VALUES ('PERCENTAGE','PERCENTAGE') ON CONFLICT DO NOTHING;


-- Add a new column to the attr_value table to store the percentage value.
ALTER TABLE attr_value ADD COLUMN IF NOT EXISTS value_percentage PERCENTAGE;


-- Drop the existing constraint if it exists
ALTER TABLE attr_value DROP CONSTRAINT IF EXISTS attr_value_check1;

-- Add the new constraint
ALTER TABLE attr_value ADD CONSTRAINT attr_value_check1 CHECK (
    (
        (value_integer IS NOT NULL )::INTEGER +      
        (value_text IS NOT NULL )::INTEGER +         
        (value_integer_range IS NOT NULL )::INTEGER +
        (value_boolean IS NOT NULL )::INTEGER +      
        (value_text_list IS NOT NULL )::INTEGER +    
        (value_daterange IS NOT NULL )::INTEGER +
        (value_tstzrange IS NOT NULL )::INTEGER +
        (value_integer_list IS NOT NULL )::INTEGER +
        (value_regex IS NOT NULL )::INTEGER +
        (value_percentage IS NOT NULL )::INTEGER
    ) = 1
);

-- Update the 'v_attr_value' view to include the new column.
CREATE OR REPLACE VIEW v_attr_value AS
SELECT
    tn.id AS tenant_id,
    tn.name AS tenant_name,
    k.category_id,
    ag.name AS category_name,
    k.id AS key_id,
    k.name AS key_name,
    vt.name AS data_type_name,
    vt.data_type,
    COALESCE(
        av.value_integer::TEXT,      
        av.value_text::TEXT,         
        av.value_integer_range::TEXT,
        av.value_boolean::TEXT,      
        av.value_text_list::TEXT,    
        av.value_integer_list::TEXT,
        av.value_daterange::TEXT,
        av.value_tstzrange::TEXT,
        av.value_regex::TEXT,
        av.value_percentage::TEXT,
        k.default_value::TEXT
    ) AS value,
    av.id IS NULL AS is_default,
    av.tld_id,
    av.provider_instance_id,
    av.provider_id,
    av.registry_id
FROM attr_key k
    JOIN tenant tn ON TRUE
    JOIN attr_category ag ON ag.id = k.category_id
    JOIN attr_value_type vt ON vt.id = k.value_type_id
    LEFT JOIN attr_value av ON av.key_id = k.id AND tn.id = av.tenant_id
;


-- function: attr_value_insert()
-- description: validates the value of the attribute based on the key configuration.
CREATE OR REPLACE FUNCTION attr_value_insert() RETURNS TRIGGER AS $$
DECLARE
    _key_config RECORD;
    _total_null INT;
    _is_null BOOLEAN;
BEGIN
    SELECT 
        ak.*,
        avt.name AS data_type_name,
        avt.data_type AS data_type 
    INTO _key_config 
    FROM attr_key ak 
        JOIN attr_value_type avt ON avt.id=ak.value_type_id 
    WHERE ak.id = NEW.key_id;

    -- let's make sure that only one value was entered:
    _total_null := (NEW.value_integer IS NULL )::INTEGER +      
                   (NEW.value_text IS NULL )::INTEGER +         
                   (NEW.value_integer_range IS NULL )::INTEGER +
                   (NEW.value_boolean IS NULL )::INTEGER +      
                   (NEW.value_text_list IS NULL )::INTEGER +    
                   (NEW.value_integer_list IS NULL )::INTEGER + 
                   (NEW.value_daterange IS NULL )::INTEGER +
                   (NEW.value_tstzrange IS NULL )::INTEGER +
                   (NEW.value_regex IS NULL )::INTEGER +
                   (NEW.value_percentage IS NULL )::INTEGER;

    -- if all the values are NULL, we check to see if we allow NULL
    IF _total_null = 0 THEN 
        IF NOT _key_config.allow_null THEN 
            RAISE EXCEPTION 'null value not allowed for key: %s (id: %s)',
                _key_config.name,
                _key_config.id;
        ELSE
            RETURN NEW;
        END IF;
    END IF;

    -- check that the value in the NEW record is null
    EXECUTE 
        FORMAT('SELECT $1.value_%s IS NULL',_key_config.data_type_name) 
        INTO _is_null USING NEW;     

    -- if it is, we raise an exception
    IF _is_null THEN 
        RAISE EXCEPTION 'column %s must have a non-null value', _key_config.data_type_name;
    END IF;

    RETURN NEW;
END
$$ LANGUAGE PLPGSQL;
