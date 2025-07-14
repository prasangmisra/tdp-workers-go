-- db/stored-procedures.ddl

    CREATE OR REPLACE FUNCTION null_to_value(uuid)
    RETURNS uuid AS $$
    BEGIN
        RETURN COALESCE($1, '00000000-0000-0000-0000-000000000000'::uuid);
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;

    CREATE OR REPLACE FUNCTION bool_to_value(BOOLEAN) RETURNS TEXT AS $$
    SELECT CASE 
                WHEN $1 
                    THEN 0 
                    ELSE 1 
            END;
    $$ LANGUAGE SQL STRICT IMMUTABLE SECURITY DEFINER;

-- db/finance_setting/functions.ddl 
    
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
        _total_parm := 
                        (NEW.tenant_id IS NOT NULL)::INTEGER +
                        (NEW.tenant_customer_id IS NOT NULL)::INTEGER +
                        (NEW.provider_instance_tld_id IS NOT NULL)::INTEGER ; 

        IF _total_parm > 2 THEN 

            RAISE EXCEPTION 'too many given parameters for NEW.name: %', NEW.name; 
        ELSE
            IF _total_parm = 0 THEN
                RETURN NEW;
            ELSE
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

        IF ((NEW.value_integer IS NOT NULL)::INTEGER +      
            (NEW.value_text IS NOT NULL)::INTEGER +         
            (NEW.value_boolean IS NOT NULL)::INTEGER +      
            (NEW.value_decimal IS NOT NULL)::INTEGER +   
            (NEW.value_uuid IS NOT NULL)::INTEGER +   
            (NEW.value_text_list IS NOT NULL)::INTEGER) <> 1 THEN
            RAISE EXCEPTION 'Only one value column can be NOT NULL NEW.value_integer %,NEW.value_text %, NEW.value_boolean %, NEW.value_decimal %, NEW.value_text_list %', NEW.value_integer, NEW.value_text, NEW.value_boolean, NEW.value_decimal, NEW.value_text_list;
        END IF;

        IF (
            (NEW.tenant_id IS NOT NULL)::INTEGER +
            (NEW.tenant_customer_id IS NOT NULL)::INTEGER +
            (NEW.provider_instance_tld_id IS NOT NULL)::INTEGER) > 2 THEN
            RAISE EXCEPTION 'At most two of tenant_id, tenant_customer_id, provider_instance_tld_id can be NOT NULL';
        END IF;

        IF _finance_setting ~ '^general\.' THEN
            IF NEW.provider_instance_tld_id IS NOT NULL OR _finance_settingtld_id IS NOT NULL OR NEW.tenant_id IS NOT NULL OR NEW.tenant_customer_id IS NOT NULL THEN
                RAISE EXCEPTION 'General settings cannot have provider_instance_tld_id, tenant_id, or tenant_customer_id';
            END IF;
        END IF;

        IF _finance_setting ~ '^tenant\.' THEN
            IF NEW.tenant_id IS NULL OR NEW.tenant_customer_id IS NOT NULL OR NEW.provider_instance_tld_id IS NOT NULL THEN
                RAISE EXCEPTION 'Tenant settings must have tenant_id and cannot have tenant_customer_id, or provider_instance_tld_id';
            END IF;
        END IF;

        IF _finance_setting ~ '^provider_instance_tld\.'  THEN     
            IF NEW.provider_instance_tld_id IS NULL OR NEW.tenant_id IS NOT NULL OR NEW.tenant_customer_id IS NOT NULL THEN
                RAISE EXCEPTION 'TLD settings must have provider_instance_tld_id and cannot have tenant_id, or tenant_customer_id';
            END IF;
        END IF;

        IF _finance_setting ~ '^tenant_customer\.' THEN
            IF NEW.tenant_customer_id IS NULL OR NEW.provider_instance_tld_id IS NOT NULL OR NEW.tenant_id IS NOT NULL THEN
                RAISE EXCEPTION 'Tenant Customer settings must have tenant_customer_id and cannot have provider_instance_tld_id, tenant_id';
            END IF;
        END IF;

        IF _finance_setting ~ '^tenant_customer\..*\.provider_instance_tld\.' THEN
            IF NEW.tenant_customer_id IS NULL OR NEW.provider_instance_tld_id IS NULL OR NEW.tenant_id IS NOT NULL  THEN
                RAISE EXCEPTION 'Tenant Customer TLD settings must have tenant_customer_id and provider_instance_tld_id and cannot have tenant_id ';
            END IF;
        END IF;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

-- db/finance_setting/schema.ddl 
    CREATE TABLE IF NOT EXISTS finance_setting_type (
        id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name                    TEXT NOT NULL, 
        descr                   TEXT NOT NULL,
        UNIQUE ("name"));

    CREATE INDEX idx_finance_setting_type_name ON finance_setting_type (name);

    CREATE TABLE IF NOT EXISTS finance_setting (
        id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id                   UUID REFERENCES tenant,
        tenant_customer_id          UUID REFERENCES tenant_customer,
        provider_instance_tld_id    UUID REFERENCES provider_instance_tld,
        type_id     UUID NOT NULL REFERENCES finance_setting_type, 
        value_integer               INTEGER, 
        value_decimal               DECIMAL(19, 4), 
        value_text                  TEXT, 
        value_uuid                  UUID,  
        value_boolean               BOOLEAN, 
        value_text_list             TEXT[], 
        validity 				    TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
        EXCLUDE USING gist (type_id WITH=, 
            COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            COALESCE(tenant_customer_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            COALESCE(provider_instance_tld_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            validity WITH &&) 
    ) INHERITS (class.audit, class.soft_delete);

    CREATE INDEX idx_finance_setting_tenant_id ON finance_setting (tenant_id);
    CREATE INDEX idx_finance_setting_tenant_customer_id ON finance_setting (tenant_customer_id);
    CREATE INDEX idx_finance_setting_provider_instance_tld_id ON finance_setting (provider_instance_tld_id);
    CREATE INDEX idx_type_id ON finance_setting (type_id);

-- db/finance_setting/views.ddl 
    CREATE OR REPLACE VIEW v_finance_setting AS 
    SELECT 
        fst.name, 
        COALESCE(
            fs.value_integer::TEXT,    
            fs.value_decimal::TEXT, 
            fs.value_text::TEXT,  
            fs.value_boolean::TEXT, 
            fs.value_uuid::TEXT, 
            fs.value_text_list::TEXT 
        ) AS value,
        CASE
            WHEN fs.tenant_id IS NULL 
                AND fs.tenant_customer_id IS NULL 
                AND fs.provider_instance_tld_id IS NULL 
            THEN TRUE
            ELSE FALSE
        END AS is_default, 
        fs.id, 
        fs.tenant_id,
        fs.tenant_customer_id,
        fs.provider_instance_tld_id,
        fs.type_id,
        "fs".validity
        FROM finance_setting fs 
        JOIN finance_setting_type fst ON fst.id = fs.type_id
        ORDER BY fst.name, is_default DESC; 

-- db/finance_setting/init.sql 

    INSERT INTO finance_setting_type (name, descr)
    VALUES
        ('general.margin_cap', 'Cap margin on premium domains at $1,000'),
        ('general.round_up_premium', 'Round to nearest $X increment'),
        ('general.round_up_non_premium', 'Round to nearest $X increment'),
        ('general.currency_fluctuation', 'Alert when currency check brings in a fluctuation of currency relative to the existing current value larger than a certain percent'),
        ('general.icann_fee', 'Cost Component ICANN Fee'),
        ('general.bank_fee', 'Cost Component Bank Fee Percentage'),
        ('general.intercompany_pricing_fee', 'Cost Component Intercompany Pricing Fee Percentage'),
        ('general.icann_fee_currency_type', 'Currency_type for Cost Component ICANN Fee'),
        ('provider_instance_tld.is_linear_registryfee_create', 'Is Linear Registry Fee for order_type Domain Create for TLD'),
        ('provider_instance_tld.is_linear_registryfee_renew', 'Is Linear Registry Fee for order_type Domain Renew for TLD'),
        ('provider_instance_tld.accepts_currency', 'Default Currency for TLD'),
        ('provider_instance_tld.tax_fee', 'Cost Component Tax Fee Percentage Depends on TLD'),
        ('tenant_customer.default_currency', 'Default Currency for Tenant Customer'),
        ('tenant_customer.provider_instance_tld.specific_currency', 'Specific Currency to Bill The Customer for The Specific TLD'), 
        ('tenant.accepts_currencies', 'Currency (Abbreviation) Exempt From Bank Fees'),
        ('tenant.hrs','HRS Tenant Boolean Default FALSE'),
        ('tenant.customer_of','the HRS tenant is a customer of tenant_id') 
    ON CONFLICT DO NOTHING;

    INSERT INTO finance_setting (type_id, value_integer, validity)
    VALUES
        (tc_id_from_name('finance_setting_type','general.margin_cap'), 100000, tstzrange('2024-01-01 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type','general.round_up_premium'), 1000,  tstzrange('2024-01-01 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type','general.round_up_non_premium'), 500, tstzrange('2024-01-01 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type','general.currency_fluctuation'), 5, tstzrange('2024-01-01 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type','general.icann_fee'), 18, tstzrange('2013-01-01 00:00:00 UTC', '2025-07-01 00:00:00 UTC')),
        (tc_id_from_name('finance_setting_type','general.icann_fee'), 20, tstzrange('2025-07-01 00:00:00 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type','general.bank_fee'), 2, tstzrange('2024-01-01 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type','general.intercompany_pricing_fee'), 5, tstzrange('2024-01-01 UTC', 'infinity'))
    ON CONFLICT DO NOTHING;

    INSERT INTO finance_setting (type_id, value_text, validity)
    VALUES
        (tc_id_from_name('finance_setting_type','general.icann_fee_currency_type'), 'USD', tstzrange('2024-01-01 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type','provider_instance_tld.accepts_currency'), 'USD', tstzrange('2024-01-01 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type', 'tenant_customer.default_currency'), 'USD', tstzrange('2024-01-01 UTC', 'infinity'))
    ON CONFLICT DO NOTHING;

    INSERT INTO finance_setting (type_id, value_text_list, validity)
    VALUES
        (tc_id_from_name('finance_setting_type','tenant.accepts_currencies'), ARRAY['USD'], tstzrange('2024-01-01 UTC', 'infinity'))
    ON CONFLICT DO NOTHING;

    INSERT INTO finance_setting (type_id, value_boolean, validity)
    VALUES 
        (tc_id_from_name('finance_setting_type','provider_instance_tld.is_linear_registryfee_create'), 'TRUE', tstzrange('2024-01-01 UTC', 'infinity')),
        (tc_id_from_name('finance_setting_type','provider_instance_tld.is_linear_registryfee_renew'), 'TRUE', tstzrange('2024-01-01 UTC', 'infinity'))
    ON CONFLICT DO NOTHING;

    INSERT INTO finance_setting (type_id, value_decimal, validity)
    VALUES 
        (tc_id_from_name('finance_setting_type','provider_instance_tld.tax_fee'), 0, tstzrange('2024-01-01 UTC', 'infinity'))
    ON CONFLICT DO NOTHING;

-- db/finance_setting/triggers.ddl
    CREATE OR REPLACE TRIGGER a_check_finance_setting_constraints_tg
        BEFORE INSERT OR UPDATE ON finance_setting
        FOR EACH ROW 
        EXECUTE FUNCTION check_finance_setting_constraints();

    CREATE OR REPLACE TRIGGER b_finance_setting_insert_tg
        BEFORE INSERT ON finance_setting
        FOR EACH ROW
        EXECUTE FUNCTION finance_setting_insert();





