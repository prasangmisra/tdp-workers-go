-- function: get_finance_setting(parameters)
-- description: function returns either desired value for given parameters or default value; 
-- parameters needed: 
-- 1. p_name: name of the parameter; it can start with parameter type (general. | tenant_customer. | tenant. | provider_instance_tld.)
--    followed by wither name or another parameter type and then name; 
-- example 
--    'general.margin_cup' 
--    'tenant_customer.default_currency' - only parameter . name 
--    'tenant_customer.provider_instance_tld.specific_currency‘ - 1st parameter . 2nd parameter . name
-- 2. p_tenant_customer_id takes tenant_customer_id; 
-- 3. p_tenant_id takes tenant_id; 
-- 4. p_provider_instance_tld_id takes provider_instance_tld_id; 
-- 5. p_date takes tztstimestamp default NOW - useful for future; 

CREATE OR REPLACE FUNCTION get_finance_setting(
    p_name TEXT, 
    p_tenant_customer_id UUID DEFAULT NULL, 
    p_tenant_id UUID DEFAULT NULL,
    p_provider_instance_tld_id UUID DEFAULT NULL,
    p_date TIMESTAMP WITH TIME ZONE DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    _finance_setting TEXT;
    _default TEXT; 
BEGIN

    IF p_date IS NULL THEN
        p_date := CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
    END IF; 

    SELECT v.value
        INTO _default
    FROM v_finance_setting v
    WHERE v.name = p_name
        AND v.is_default IS TRUE; 

    SELECT v.value
        INTO _finance_setting
    FROM v_finance_setting v
    WHERE v.name = p_name
        AND v.validity @> p_date 
        AND (CASE
                WHEN p_tenant_customer_id IS NOT NULL 
                    THEN v.tenant_customer_id = p_tenant_customer_id 
                    ELSE v.tenant_customer_id IS NULL
            END)
        AND (CASE    
                WHEN p_tenant_id IS NOT NULL 
                    THEN v.tenant_id = p_tenant_id 
                    ELSE v.tenant_id IS NULL
            END)
        AND (CASE
                WHEN p_provider_instance_tld_id IS NOT NULL 
                    THEN v.provider_instance_tld_id = p_provider_instance_tld_id
                    ELSE v.provider_instance_tld_id IS NULL
            END); 

    -- Check if a setting was found
    IF _finance_setting IS NULL AND _default IS NULL THEN
        RAISE NOTICE 'No setting found for p_name %', p_name;
        RETURN NULL;

    ELSEIF _finance_setting IS NULL AND _default IS NOT NULL THEN
        RETURN _default;
        
    ELSE
        RETURN _finance_setting;
    END IF;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION finance_setting_insert() RETURNS TRIGGER AS $$
DECLARE
    _default RECORD;
    _total_parm INT;

BEGIN
    -- one cant enter exception without first enering the default value 
    -- check if 1. it is a default record - all the uuids & names are nULL; if it is then proceed with insertion; else it sould have existing record with the same name in finance_setting; if it is not here, then dont allow to insert record
    

    -- let's check if we recieved more then 1 parameter &
    _total_parm := 
                    (NEW.tenant_id IS NOT NULL)::INTEGER +
                    (NEW.tenant_customer_id IS NOT NULL)::INTEGER +
                    (NEW.provider_instance_tld_id IS NOT NULL)::INTEGER ; 

    -- if all the values are NULL, we input new default value 
    IF _total_parm > 2 THEN 

        RAISE EXCEPTION 'too many given parameters for NEW.name: %', NEW.name; 
    ELSE
        -- Check if it is a default record
        IF _total_parm = 0 THEN
            RETURN NEW;
        ELSE
            -- let's check if 1 parameter present than it should have default walue to override before insert the override
            -- Check if there is an existing record with the same name in finance_setting
            SELECT 1
            INTO _default
            FROM v_finance_setting v
            WHERE v.type_id = NEW.type_id
            LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'No existing record found for NEW.finance_setting: %', NEW.name;
            ELSE
                RETURN NEW;
            END IF;
        END IF;
    END IF;            
END
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION check_finance_setting_constraints()
RETURNS TRIGGER AS $$
DECLARE
    _finance_setting TEXT; 
BEGIN
    SELECT fst.name AS name
        INTO _finance_setting
    FROM finance_setting fs 
    JOIN finance_setting_type fst ON fst.id = fs.type_id
    WHERE fs.id = NEW.id;

    RAISE NOTICE '_finance_setting %',_finance_setting; 

    -- Ensure only one value column is NOT NULL
    IF ((NEW.value_integer IS NOT NULL)::INTEGER +      
        (NEW.value_text IS NOT NULL)::INTEGER +         
        (NEW.value_boolean IS NOT NULL)::INTEGER +      
        (NEW.value_decimal IS NOT NULL)::INTEGER +   
        (NEW.value_uuid IS NOT NULL)::INTEGER +   
        (NEW.value_text_list IS NOT NULL)::INTEGER) <> 1 THEN
        RAISE EXCEPTION 'Only one value column can be NOT NULL NEW.value_integer %,NEW.value_text %, NEW.value_boolean %, NEW.value_decimal %, NEW.value_text_list %', NEW.value_integer, NEW.value_text, NEW.value_boolean, NEW.value_decimal, NEW.value_text_list;
    END IF;

    -- Ensure at most two of the columns (tenant_id, tenant_customer_id, provider_instance_tld_id) are NOT NULL
    IF (
        (NEW.tenant_id IS NOT NULL)::INTEGER +
        (NEW.tenant_customer_id IS NOT NULL)::INTEGER +
        (NEW.provider_instance_tld_id IS NOT NULL)::INTEGER) > 2 THEN
        RAISE EXCEPTION 'At most two of tenant_id, tenant_customer_id, provider_instance_tld_id can be NOT NULL';
    END IF;

    -- General settings
    IF _finance_setting ~ '^general\.' THEN
        IF NEW.provider_instance_tld_id IS NOT NULL OR _finance_settingtld_id IS NOT NULL OR NEW.tenant_id IS NOT NULL OR NEW.tenant_customer_id IS NOT NULL THEN
            RAISE EXCEPTION 'General settings cannot have provider_instance_tld_id, tenant_id, or tenant_customer_id';
        END IF;
    END IF;

    -- Tenant settings
    IF _finance_setting ~ '^tenant\.' THEN
        IF NEW.tenant_id IS NULL OR NEW.tenant_customer_id IS NOT NULL OR NEW.provider_instance_tld_id IS NOT NULL THEN
            RAISE EXCEPTION 'Tenant settings must have tenant_id and cannot have tenant_customer_id, or provider_instance_tld_id';
        END IF;
    END IF;

    -- TLD settings
    IF _finance_setting ~ '^provider_instance_tld\.'  THEN     
        IF NEW.provider_instance_tld_id IS NULL OR NEW.tenant_id IS NOT NULL OR NEW.tenant_customer_id IS NOT NULL THEN
            RAISE EXCEPTION 'TLD settings must have provider_instance_tld_id and cannot have tenant_id, or tenant_customer_id';
        END IF;
    END IF;

    -- Tenant Customer settings
    IF _finance_setting ~ '^tenant_customer\.' THEN
        IF NEW.tenant_customer_id IS NULL OR NEW.provider_instance_tld_id IS NOT NULL OR NEW.tenant_id IS NOT NULL THEN
            RAISE EXCEPTION 'Tenant Customer settings must have tenant_customer_id and cannot have provider_instance_tld_id, tenant_id';
        END IF;
    END IF;

    -- Tenant Customer TLD settings
    IF _finance_setting ~ '^tenant_customer\..*\.provider_instance_tld\.' THEN
        IF NEW.tenant_customer_id IS NULL OR NEW.provider_instance_tld_id IS NULL OR NEW.tenant_id IS NOT NULL  THEN
            RAISE EXCEPTION 'Tenant Customer TLD settings must have tenant_customer_id and provider_instance_tld_id and cannot have tenant_id ';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;