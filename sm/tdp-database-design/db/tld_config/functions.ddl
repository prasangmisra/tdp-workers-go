-- function: attribute_update()
-- description: Updates the attribute value based on the key configuration.
CREATE OR REPLACE FUNCTION attribute_update() RETURNS TRIGGER AS $$
DECLARE
    payload JSONB;
BEGIN
    IF NEW.is_default THEN 
        EXECUTE 
            FORMAT('INSERT INTO attr_value(key_id,value_%s,tld_id,tenant_id) VALUES($1,$2::%s,$3,$4)',NEW.data_type_name,NEW.data_type) 
            USING NEW.key_id,NEW.value,NEW.tld_id,NEW.tenant_id;
    ELSE 
        EXECUTE 
            FORMAT(
                'UPDATE attr_value SET value_%s=$1::%s WHERE key_id=$2 AND tenant_id=$3 AND tld_id=$4',
                NEW.data_type_name,
                NEW.data_type
            )
            USING NEW.value,NEW.key_id, NEW.tenant_id, NEW.tld_id;
    END IF;
    
    payload := JSONB_BUILD_OBJECT(
        'tld_name', NEW.tld_name,
        'tenant_name',NEW.tenant_name,
        'key',NEW.key,
        'value', NEW.value,
        'data_type', NEW.data_type
    );

    PERFORM notify_event('cache_update', 'attribute_update_notify', payload::TEXT);

    RETURN NEW;
END
$$ LANGUAGE PLPGSQL;


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
                   (NEW.value_regex IS NULL )::INTEGER;

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


-- function: get_tld_setting
-- description: Retrieves the value of TLD setting based on provided key and either TLD ID or name, and tenant ID or name.
-- The function parameters have the following precedence:
-- 1. p_tld_id: If provided, this takes precedence over p_tld_name.
-- 2. p_tld_name: Used if p_tld_id is not provided.
-- 3. p_tenant_id: Used with tld id/name. If provided, this takes precedence over p_tenant_name.
-- 4. p_tenant_name: Used if p_tenant_id is not provided.
-- 5. p_accreditation_tld_id: Used if none of the above is provided.
CREATE OR REPLACE FUNCTION get_tld_setting(
    p_key TEXT,
    p_accreditation_tld_id UUID DEFAULT NULL,
    p_tld_id UUID DEFAULT NULL,
    p_tld_name TEXT DEFAULT NULL,
    p_tenant_id UUID DEFAULT NULL,
    p_tenant_name TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    _tld_setting    TEXT;
    v_tld_id        UUID;
    v_tenant_id     UUID;
BEGIN
    -- Determine the TLD ID
    IF p_tld_id IS NOT NULL AND v_tld_id IS NULL THEN
        v_tld_id := p_tld_id;
    ELSIF p_tld_name IS NOT NULL AND v_tld_id IS NULL THEN
        SELECT id INTO v_tld_id FROM tld WHERE name = p_tld_name;
        IF v_tld_id IS NULL THEN
            RAISE NOTICE 'No TLD found for name %', p_tld_name;
            RETURN NULL;
        END IF;
    ELSEIF p_accreditation_tld_id IS NULL THEN
        RAISE NOTICE 'At least one of the following must be provided: TLD ID/name or accreditation_tld ID';
        RETURN NULL;
    END IF;

    -- Determine the Tenant ID
    IF p_tenant_id IS NOT NULL THEN
        v_tenant_id := p_tenant_id;
    ELSIF p_tenant_name IS NOT NULL THEN
        SELECT tenant_id INTO v_tenant_id FROM v_tenant_customer WHERE tenant_name = p_tenant_name;
        IF v_tenant_id IS NULL THEN
            RAISE NOTICE 'No tenant found for name %', p_tenant_name;
            RETURN NULL;
        END IF;
    END IF;

    -- Determine the TLD ID/Tenant ID from accreditation tld id
    IF p_accreditation_tld_id IS NOT NULL AND v_tld_id IS NULL AND v_tenant_id IS NULL THEN
        SELECT value INTO _tld_setting
        FROM v_attribute va
        WHERE (va.key = p_key OR va.key LIKE '%.' || p_key)
          AND va.accreditation_tld_id = p_accreditation_tld_id;
        RETURN _tld_setting;
    END IF;

    -- Retrieve the setting value from the v_attribute
    IF v_tenant_id IS NOT NULL THEN
        SELECT value INTO _tld_setting
        FROM v_attribute va
        WHERE (va.key = p_key OR va.key LIKE '%.' || p_key)
          AND va.tld_id = v_tld_id
          AND va.tenant_id = v_tenant_id;
    ELSE
        SELECT value INTO _tld_setting
        FROM v_attribute va
        WHERE (va.key = p_key OR va.key LIKE '%.' || p_key)
          AND va.tld_id = v_tld_id;
    END IF;

    -- Check if a setting was found
    IF _tld_setting IS NULL THEN
        RAISE NOTICE 'No setting found for key %, TLD ID %, and tenant ID %', p_key, v_tld_id, v_tenant_id;
        RETURN NULL;
    ELSE
        RETURN _tld_setting;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- function: get_tld_setting_by_tenant_customer_id
-- description: Retrieves the value of TLD setting based on provided key and either TLD ID or name, and tenant customer ID.
CREATE OR REPLACE FUNCTION get_tld_setting_by_tenant_customer_id(
    p_key                   TEXT,
    p_tenant_customer_id    UUID,
    p_tld_id                UUID DEFAULT NULL,
    p_tld_name              TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    _tenant_id      UUID;
BEGIN
    -- either p_tld_name or p_tld_id must be provided
    IF p_tld_name IS NULL AND p_tld_id IS NULL THEN
        RAISE EXCEPTION 'Either TLD name or TLD ID must be provided';
    END IF;

    -- Get the tenant ID
    SELECT tenant_id INTO _tenant_id
    FROM tenant_customer
    WHERE id = p_tenant_customer_id;

    IF _tenant_id IS NULL THEN
        RAISE NOTICE 'No tenant found for tenant customer ID %', p_tenant_customer_id;
        RETURN NULL;
    END IF;

    -- Retrieve the TLD setting
    RETURN get_tld_setting(
        p_key=>p_key,
        p_tld_id=>p_tld_id,
        p_tld_name=>p_tld_name,
        p_tenant_id=>_tenant_id
    );
END;
$$ LANGUAGE plpgsql;
