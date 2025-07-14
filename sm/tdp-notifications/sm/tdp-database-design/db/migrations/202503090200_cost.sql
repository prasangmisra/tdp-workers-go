-- db/backend_provider/schema.ddl
    ALTER TABLE tld 
        ADD COLUMN IF NOT EXISTS type_id UUID REFERENCES tld_type;

    UPDATE tld
    SET type_id = CASE
        WHEN LENGTH(tld.name) = 2 
            THEN tc_id_from_name('tld_type','country_code')
        ELSE tc_id_from_name('tld_type','generic')
        END;

    ALTER TABLE tld
        ALTER COLUMN type_id SET NOT NULL;

    DROP TABLE IF EXISTS tld_type_tld;

-- db.cost/stored-procedures/generate_sku.ddl

    CREATE OR REPLACE FUNCTION generate_sku()
    RETURNS TEXT AS $$
    DECLARE
        random_chars TEXT;
    BEGIN
        SELECT string_agg(round(random() * 9)::integer::text, '') 
        INTO random_chars FROM generate_series(1, 8);

        RETURN 'sku' || random_chars;
    END;
    $$ LANGUAGE plpgsql;

-- db/cost/schema.ddl

    CREATE TABLE IF NOT EXISTS period_type(
        id 				              UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
        "name" 			              TEXT NOT NULL,
        UNIQUE ("name")
    )INHERITS (class.audit);
    CREATE INDEX idx_period_type_name ON period_type("name");

    CREATE TABLE IF NOT EXISTS order_type_period_type(
        id 				                UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
        order_type_id 			        UUID NOT NULL REFERENCES order_type,
        period_type_id                  UUID NOT NULL REFERENCES period_type, 
        UNIQUE (order_type_id, period_type_id)
    );
    CREATE INDEX idx_order_type_period_type_order_type_id ON order_type_period_type(order_type_id);
    CREATE INDEX idx_order_type_period_type_period_type_id ON order_type_period_type(period_type_id);

    CREATE TABLE IF NOT EXISTS currency_exchange_rate( 
        id 				              UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
        currency_type_id              UUID NOT NULL REFERENCES currency_type, 
        value 			              DECIMAL(19, 4) NOT NULL,
        validity 		              TSTZRANGE NOT NULL CHECK (NOT isempty(validity))
    )INHERITS (class.audit);
    CREATE INDEX idx_exchange_rate_currency_type_id ON  currency_exchange_rate(currency_type_id);

    CREATE TABLE IF NOT EXISTS cost_type (
        id 			    UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
        "name" 		  TEXT NOT NULL,
        descr 		  TEXT not NULL,
        UNIQUE ("name")
    )INHERITS (class.audit);
    CREATE INDEX idx_cost_type_name ON  cost_type("name");

    CREATE TABLE IF NOT EXISTS cost_component_type (
    id 						    UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
    "name" 					    TEXT NOT NULL,
    cost_type_id                  UUID NOT NULL REFERENCES cost_type,
    is_periodic			        BOOLEAN NOT NULL DEFAULT TRUE,
    is_percent                    BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE ("name")
    )INHERITS (class.audit);
    CREATE INDEX idx_cost_component_type_name ON  cost_component_type("name");
    CREATE INDEX idx_cost_component_type_cost_type_id ON  cost_component_type(cost_type_id);
    CREATE INDEX idx_cost_component_type_is_periodic ON  cost_component_type(is_periodic);
    CREATE INDEX idx_cost_component_type_is_percent ON  cost_component_type(is_percent);

    CREATE TABLE IF NOT EXISTS  cost_product_strategy (
    id                                  UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
    order_type_id                       UUID NOT NULL REFERENCES order_type, 
    cost_component_type_id              UUID NOT NULL REFERENCES cost_component_type,
    calculation_sequence                INTEGER NOT NULL, 
    is_in_total_cost                    BOOLEAN NOT NULL DEFAULT TRUE,	
    UNIQUE (order_type_id, cost_component_type_id)
    )INHERITS (class.audit);
    CREATE INDEX idx_product_cost_strategy_order_type_id ON  cost_product_strategy(order_type_id);
    CREATE INDEX idx_product_cost_strategy_cost_component_type_id ON  cost_product_strategy(cost_component_type_id);

    CREATE TABLE IF NOT EXISTS cost_product_component (
    id 		                              UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
    cost_component_type_id              UUID NOT NULL REFERENCES cost_component_type,
    order_type_id                       UUID REFERENCES order_type,
    period                              INTEGER DEFAULT 1,
    period_type_id                      UUID DEFAULT tc_id_from_name('period_type', 'year') REFERENCES period_type,             
    value                               DECIMAL(19, 4) NOT NULL,
    currency_type_id                    UUID DEFAULT tc_id_from_name('currency_type', 'USD') REFERENCES currency_type,
    is_promo                            BOOLEAN NOT NULL DEFAULT FALSE,
    is_promo_applied_to_1_year_only     BOOLEAN DEFAULT NULL,
    is_rebate                           BOOLEAN DEFAULT NULL,
    validity                            TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
    EXCLUDE USING gist (COALESCE(cost_component_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
                COALESCE(order_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
                period WITH =,
                period_type_id WITH =,
                COALESCE(currency_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
                bool_to_value(is_promo::BOOLEAN) WITH =,
                validity WITH &&)
    )INHERITS (class.audit);

    CREATE INDEX idx_product_cost_component_cost_component_type_id ON  cost_product_component(cost_component_type_id);
    CREATE INDEX idx_product_cost_component_order_type_id ON  cost_product_component(order_type_id);
    CREATE INDEX idx_product_cost_component_currency_type_id ON  cost_product_component(currency_type_id);

    CREATE TABLE IF NOT EXISTS cost_domain_component (
    accreditation_tld_id                    UUID REFERENCES accreditation_tld, 
    FOREIGN KEY (cost_component_type_id)    REFERENCES cost_component_type,
    FOREIGN KEY (order_type_id)             REFERENCES order_type,
    FOREIGN KEY (currency_type_id)          REFERENCES currency_type, 
    FOREIGN KEY (period_type_id)            REFERENCES period_type,
    PRIMARY KEY (id),
    EXCLUDE USING gist (COALESCE(cost_component_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
                COALESCE(accreditation_tld_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
                COALESCE(order_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
                period WITH =,
                period_type_id WITH =,
                COALESCE(currency_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
                bool_to_value(is_promo::BOOLEAN) WITH =,
                validity WITH &&)
    ) INHERITS (cost_product_component);

    CREATE INDEX idx_cost_domain_component_cost_component_type_id ON  cost_domain_component(cost_component_type_id);
    CREATE INDEX idx_cost_domain_component_accreditation_tld_id ON  cost_domain_component(accreditation_tld_id);
    CREATE INDEX idx_cost_domain_component_order_type_id ON  cost_domain_component(order_type_id);
    CREATE INDEX idx_cost_domain_component_currency_type_id ON  cost_domain_component(currency_type_id);

    CREATE TABLE IF NOT EXISTS  stock_keeping_unit(
    id                       	  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    sku                         TEXT NOT NULL DEFAULT generate_sku(),  
    order_type_period_type_id   UUID NOT NULL REFERENCES order_type_period_type, -- product_id, order_type_id, period_type_id
    UNIQUE (order_type_period_type_id)
    )INHERITS (class.audit);

    CREATE INDEX idx_stock_keeping_unit_order_type_period_type_id ON  stock_keeping_unit(order_type_period_type_id);

    CREATE TABLE IF NOT EXISTS  stock_keeping_unit_domain(
    accreditation_tld_id          UUID NOT NULL REFERENCES accreditation_tld, 
    FOREIGN KEY (order_type_period_type_id)   REFERENCES order_type_period_type, 
    PRIMARY KEY (id),
    UNIQUE (accreditation_tld_id, order_type_period_type_id)
    ) INHERITS (stock_keeping_unit, class.soft_delete);

    CREATE INDEX idx_domain_stock_keeping_unit_accreditation_tld_id ON  stock_keeping_unit_domain(accreditation_tld_id);
    CREATE INDEX idx_domain_stock_keeping_unit_order_type_period_type_id ON  stock_keeping_unit_domain(order_type_period_type_id);

-- db/cost/init.sql 

    INSERT INTO period_type("name")
        VALUES 
        ('month'),
        ('quarter'),
        ('year'),
        ('transaction')
    ON CONFLICT DO NOTHING; 

    INSERT INTO order_type_period_type
        (order_type_id, period_type_id)
        SELECT  
            ot.id, 
            CASE WHEN ot.name IN ('create','renew') THEN tc_id_from_name('period_type', 'year')
            ELSE tc_id_from_name('period_type', 'transaction')
            END
        FROM order_type ot
        JOIN product p ON ot.product_id = p.id
        WHERE p.name = 'domain'
    ON CONFLICT DO NOTHING;

    INSERT INTO currency_type (name, descr, fraction)
        VALUES 
            ('AUD','Australia Dollar', 100), 
            ('CAD','Canada Dollar', 100), 
            ('CHF','Swiss Franc', 100),
            ('CNY','China Yuan', 100),
            ('EUR','Euro', 100), 
            ('GBP','Great Britain Pound', 100),
            ('INR','Indian Rupee', 100), 
            ('JPY','Japanese Yen', 100),
            ('NZD','New Zealand Dollar', 100),
            ('PEN','Peru Sol', 100),
            ('SEK','Sweden Krona', 100)
        ON CONFLICT DO NOTHING;

    INSERT INTO currency_exchange_rate (currency_type_id, value, validity) 
        VALUES 
            (tc_id_from_name('currency_type', 'AUD'), 0.65885, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'CAD'), 0.75885, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'CHF'), 1.27641, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'CNY'), 0.14637, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'EUR'), 1.0924, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'GBP'), 1.27641, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'INR'), 0.01191, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'JPY'), 0.00679, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'NZD'), 0.6315, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'PEN'), 0.2925, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'SEK'), 0.1065, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamp with time zone)),
            (tc_id_from_name('currency_type', 'USD'), 1.0000, tstzrange(date_trunc('month', CURRENT_DATE)::timestamp with time zone, 'infinity', '[]'))
        ON CONFLICT DO NOTHING;   

    INSERT INTO cost_type
        ("name", descr)
        VALUES( 
            UNNEST(ARRAY[
                'fee'
                ,'repeating fee'
            ]),
            UNNEST(ARRAY[
                'The total cost for a product and order type for a given brand, vendor, product, order type, period, and validity.'
                ,'A repeating cost that needs to be tracked for a vendor or product but is not tied to any specific order or price, e.g., a yearly accreditation fee.'
            ])
        )ON CONFLICT DO NOTHING; 

    INSERT INTO cost_component_type 
        ("name", cost_type_id, is_periodic, is_percent)
        VALUES 
        ('icann fee', tc_id_from_name('cost_type', 'fee'), TRUE, FALSE), 
        ('bank fee', tc_id_from_name('cost_type', 'fee'), TRUE, TRUE), 
        ('sales tax fee', tc_id_from_name('cost_type', 'fee'), TRUE,  TRUE), 
        ('intercompany pricing fee', tc_id_from_name('cost_type', 'fee'), TRUE,  TRUE), 
        ('registry fee', tc_id_from_name('cost_type', 'fee'), TRUE,  FALSE), 
        ('manual processing fee', tc_id_from_name('cost_type', 'fee'), FALSE, FALSE)
    ON CONFLICT DO NOTHING;

    INSERT INTO cost_product_strategy
        (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
        SELECT 
            ot.id,
            tc_id_from_name('cost_component_type', 'icann fee'), 
            1, 
            TRUE
        FROM order_type ot
        WHERE ot.product_id = tc_id_from_name('product','domain') 
        AND ot.name IN ('create','renew', 'transfer_in')
    ON CONFLICT DO NOTHING;

    INSERT INTO cost_product_strategy
        (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
        SELECT 
            ot.id, 
            tc_id_from_name('cost_component_type', 'bank fee'), 
            10, 
            TRUE
        FROM order_type ot
        WHERE ot.product_id = tc_id_from_name('product','domain') 
        AND ot.name IN ('create','renew', 'transfer_in', 'redeem')
    ON CONFLICT DO NOTHING;

    INSERT INTO cost_product_strategy
        (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
        SELECT 
            ot.id, 
            tc_id_from_name('cost_component_type', 'sales tax fee'), 
            11,  
            TRUE
        FROM order_type ot
        WHERE ot.product_id = tc_id_from_name('product','domain') 
        AND ot.name IN ('create','renew', 'transfer_in', 'redeem')
    ON CONFLICT DO NOTHING;

    INSERT INTO cost_product_strategy
        (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
        SELECT 
            ot.id, 
            tc_id_from_name('cost_component_type', 'intercompany pricing fee'), 
            12,  
            FALSE
        FROM order_type ot
        WHERE ot.product_id = tc_id_from_name('product','domain') 
        AND ot.name IN ('create','renew', 'transfer_in', 'redeem')
    ON CONFLICT DO NOTHING;

    INSERT INTO cost_product_strategy
        (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
        SELECT 
            ot.id, 
            tc_id_from_name('cost_component_type', 'registry fee'), 
            30, 
            TRUE
        FROM order_type ot
        WHERE ot.product_id = tc_id_from_name('product','domain') 
        AND ot.name IN ('create','renew', 'transfer_in', 'redeem')
    ON CONFLICT DO NOTHING;

    INSERT INTO cost_product_strategy
        (order_type_id, cost_component_type_id, calculation_sequence, is_in_total_cost)
        SELECT 
            ot.id, 
            tc_id_from_name('cost_component_type', 'manual processing fee'), 
            20, 
            TRUE
        FROM order_type ot
        WHERE ot.product_id = tc_id_from_name('product','domain') 
        AND ot.name IN ('create','renew', 'transfer_in', 'redeem')
    ON CONFLICT DO NOTHING;

-- db/cost/stored-procedures/helpers.ddl 

    CREATE OR REPLACE FUNCTION refresh_mv_cost_domain_component()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_cost_domain_component;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_currency_exchange_rate()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_currency_exchange_rate;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_order_type_period_type()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_type_period_type;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_cost_product_strategy()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_cost_product_strategy;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION get_order_type_id( _order_type TEXT, _product TEXT) 
    RETURNS UUID AS $$
    DECLARE
    _result UUID;
    BEGIN
        SELECT vot.id 
            INTO _result
        FROM v_order_type vot
            WHERE vot."name" = _order_type
                AND vot.product_name = _product ; 
    RETURN _result;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;

    CREATE OR REPLACE FUNCTION get_tenant_customer_id ( _tenant TEXT, _customer TEXT) 
    RETURNS UUID AS $$
    DECLARE
        _result UUID;
    BEGIN
        SELECT tc.id 
            INTO _result
        FROM v_tenant_customer tc
        WHERE tc.tenant_name  =  _tenant
        AND tc.name  =  _customer ;
        RETURN _result;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;

    CREATE OR REPLACE FUNCTION get_accreditation_tld_id( _tenant TEXT, _tld TEXT) 
    RETURNS UUID AS $$
    DECLARE
        _result UUID;
    BEGIN
        SELECT act.accreditation_tld_id
            INTO _result
        FROM v_accreditation_tld act
        WHERE act.tld_name = _tld
    	    AND act.tenant_name = _tenant; 
        RETURN _result;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;

    CREATE OR REPLACE FUNCTION get_nonpromo_cost(_accreditation_tld_id UUID, _order_type_id UUID, _period INTEGER DEFAULT 1, 
        _period_type_id UUID DEFAULT tc_id_from_name('period_type','year'))
    RETURNS INTEGER AS $$ 
    DECLARE
        _result INTEGER;
    BEGIN
        SELECT CASE WHEN dcc.period = _period THEN dcc.value 
                ELSE dcc.value * _period 
                END 
            INTO _result
        FROM mv_cost_domain_component dcc
        WHERE dcc.accreditation_tld_id = _accreditation_tld_id
            AND dcc.cost_component_type_id = tc_id_from_name('cost_component_type','registry fee')
            AND dcc.order_type_id = _order_type_id
            AND dcc.is_promo IS FALSE
            AND dcc.validity  @> NOW()
            AND (dcc.period = 1 
                OR dcc.period = _period)
            AND dcc.period_type_id = _period_type_id;

        RETURN _result; 
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;

    CREATE OR REPLACE FUNCTION get_provider_instance_tld_id(_accreditation_tld_id UUID)
    RETURNS UUID AS $$
    DECLARE
        _result UUID;
    BEGIN
        SELECT pit.id 
            INTO _result
        FROM accreditation_tld act 
        JOIN provider_instance_tld pit ON pit.id = act.provider_instance_tld_id 
        WHERE act.id = _accreditation_tld_id; 

        RETURN _result;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;

-- db/cost/stored-procedures/cost_calculations.ddl 

    CREATE OR REPLACE FUNCTION insert_rec_cost_domain_component( _cost_component_type_id UUID, _accreditation_tld_id UUID, _order_type_id UUID, _period INTEGER, _value DECIMAL(19, 4), _currency_type_id UUID, _validity TSTZRANGE, _is_promo BOOLEAN)
    RETURNS UUID 
    AS $$
    DECLARE
        rec UUID;
        new_uuid UUID; 
        rec_seq INTEGER; 
    BEGIN
        RAISE NOTICE 'starting  insert_rec_dcc';

        SELECT id 
            INTO rec
        FROM cost_domain_component dcc
        WHERE cost_component_type_id = _cost_component_type_id
            AND accreditation_tld_id = _accreditation_tld_id
            AND (order_type_id = _order_type_id OR (order_type_id IS NULL AND _order_type_id IS NULL))
            AND (currency_type_id = _currency_type_id OR (currency_type_id IS NULL AND _currency_type_id IS NULL))
            AND validity = _validity
            AND is_promo = _is_promo;  

        RAISE NOTICE 'FOUND RECORD in cost_domain_component %', rec; 
        RAISE NOTICE 'passed RECORD in cost_domain_component  _cost_component_type_id %, _accreditation_tld_id %, _order_type_id %, _period %, _value %, _currency_type_id %, _validity %, _is_promo %', _cost_component_type_id , _accreditation_tld_id , _order_type_id , _period , _value , _currency_type_id , _validity , _is_promo; 

        IF NOT FOUND THEN 
            INSERT INTO cost_domain_component
                (cost_component_type_id,
                accreditation_tld_id,
                order_type_id, 
                period,
                value,
                currency_type_id,
                is_promo, 
                validity)
            VALUES ( _cost_component_type_id
                , _accreditation_tld_id
                , _order_type_id
                , _period
                , _value
                , _currency_type_id
                , _is_promo
                , _validity
            )RETURNING id INTO new_uuid;  
            RETURN new_uuid;
        ELSE 
            RETURN rec;
        END IF;
    END;
    $$LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION seed_icannfee_cost_domain_component(_accreditation_tld_id UUID)
    RETURNS VOID
    AS $$
    DECLARE
        rec_check RECORD; 
    BEGIN 
        SELECT 
            get_finance_setting(p_name:= 'general.icann_fee') AS value,
            get_finance_setting(p_name:= 'general.icann_fee_currency_type') AS currency_type,
            FALSE AS is_promo
                INTO rec_check   
        FROM accreditation_tld act
        JOIN provider_instance_tld pit 
            ON pit.id = act.provider_instance_tld_id 
            AND pit.service_range @> NOW() 
        JOIN tld t 
            ON t.id = pit.tld_id 
        WHERE act.id = _accreditation_tld_id 
        AND t.type_id = tc_id_from_name('tld_type','generic')
        AND t.parent_tld_id IS NULL;

        IF FOUND THEN 
            PERFORM insert_rec_cost_domain_component(tc_id_from_name('cost_component_type', 'icann fee' ),
                                            _accreditation_tld_id::UUID, 
                                            NULL::UUID, -- order_type_id
                                            1::INTEGER, 
                                            rec_check.value::DECIMAL(19, 4),  
                                            tc_id_from_name('currency_type',rec_check.currency_type),
                                            tstzrange(NOW() AT TIME ZONE 'UTC', 'infinity'),
                                            rec_check.is_promo);
        END IF; 
    END;
    $$ LANGUAGE plpgsql;  

    CREATE OR REPLACE FUNCTION seed_bankfee_cost_domain_component(_accreditation_tld_id UUID, _tenant_id UUID)
    RETURNS VOID
    AS $$
    DECLARE
        tenant_curr_list TEXT[];
        tld_curr TEXT;
    BEGIN     

        SELECT get_finance_setting(p_name:= 'tenant.accepts_currencies', 
                                    p_tenant_id:= _tenant_id)
            INTO tenant_curr_list; 

        SELECT get_finance_setting(p_name:= 'provider_instance_tld.accepts_currency', 
                                    p_provider_instance_tld_id:= act.provider_instance_tld_id)
            INTO tld_curr     
        FROM accreditation_tld act 
        JOIN accreditation a 
            ON a.id = act.accreditation_id
        WHERE act.id = _accreditation_tld_id; 

        IF NOT (tld_curr = ANY(tenant_curr_list)) THEN
            -- RAISE NOTICE 'working bank fee 2 percent  given currency: tld_curr % not in list: tenant_curr_list %', tld_curr, tenant_curr_list;

            PERFORM insert_rec_cost_domain_component(tc_id_from_name('cost_component_type', 'bank fee'),
                                            _accreditation_tld_id::UUID, 
                                            NULL::UUID, -- order_type_id
                                            1::INTEGER, 
                                            get_finance_setting(p_name:= 'general.bank_fee')::DECIMAL(19, 4),  
                                            NULL::UUID, -- currency_type_id
                                            tstzrange(NOW() AT TIME ZONE 'UTC', 'infinity'),
                                            FALSE);
        END IF;
    END;
    $$ LANGUAGE plpgsql;   

    CREATE OR REPLACE FUNCTION seed_taxfee_cost_domain_component(_provider_instance_tld_id UUID)
    RETURNS VOID
    AS $$
    DECLARE
        rec_check RECORD; 
    BEGIN 
        SELECT get_finance_setting(p_name:= 'provider_instance_tld.tax_fee',
                p_provider_instance_tld_id:= _provider_instance_tld_id) AS value,
            FALSE AS is_promo,
            act.id AS accreditation_tld_id
            INTO rec_check
        FROM accreditation_tld act 
        JOIN provider_instance_tld pit 
            ON pit.id = act.provider_instance_tld_id 
            AND pit.service_range @> NOW() 
        WHERE pit.id = _provider_instance_tld_id; 

        IF FOUND AND rec_check.value::NUMERIC(19, 4) != 0 THEN 
            PERFORM insert_rec_cost_domain_component(tc_id_from_name('cost_component_type', 'sales tax fee'),
                                            rec_check.accreditation_tld_id, 
                                            NULL::UUID, -- order_type_id
                                            1::INTEGER, 
                                            rec_check.value::DECIMAL(19, 4),  
                                            NULL::UUID, -- currency_type_id
                                            tstzrange(NOW() AT TIME ZONE 'UTC', 'infinity'),
                                            rec_check.is_promo);
        END IF;      
    END;
    $$ LANGUAGE plpgsql;    

    CREATE OR REPLACE FUNCTION autopopulate_sku()
    RETURNS TRIGGER
    AS $$
    BEGIN 

        IF TG_TABLE_NAME = 'accreditation_tld' THEN

        INSERT INTO stock_keeping_unit_domain
            (order_type_period_type_id, accreditation_tld_id)
        SELECT 
            otpt.id,
            NEW.id, 
            otpt.id
        FROM order_type_period_type otpt 
        JOIN order_type ot ON ot.id = otpt.order_type_id
        WHERE ot.product_id = tc_id_from_name('product','domain') ; 

        ELSIF TG_TABLE_NAME = 'order_type_period_type' 
        AND NEW.product_id = tc_id_from_name('product','domain') THEN

        INSERT INTO stock_keeping_unit_domain
            (order_type_period_type_id, accreditation_tld_id)
        SELECT 
            NEW.id,
            acr.id
        FROM accreditation_tld acr;  

        END IF; 

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION get_total_cost_domain_components ( 
        _accreditation_tld_id UUID, 
        _order_type_id UUID,
        _period INTEGER DEFAULT 1, 
        _period_type_id UUID DEFAULT tc_id_from_name('period_type','year'), 
        _reg_fee INTEGER DEFAULT NULL, 
        _reg_fee_currency_type_id UUID DEFAULT NULL, 
        _date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
    RETURNS TABLE (
        cost_domain_component_id UUID, 
        cost_component_type_id UUID,
        cost_component_type TEXT,
        period INTEGER, 
        period_type_id UUID, 
        value DECIMAL(19, 4),
        currency_type_id UUID, 
        currency TEXT, 
        currency_exchange_rate DECIMAL(19, 4),
        is_promo BOOLEAN, 
        is_promo_applied_to_1_year_only BOOLEAN, 
        is_rebate BOOLEAN,
        is_premium BOOLEAN, 
        is_percent BOOLEAN,
        is_periodic BOOLEAN,
        is_in_total_cost BOOLEAN, 
        promo_reg_fee INTEGER, 
        nonpromo_reg_fee INTEGER,
        calculation_sequence INTEGER
    )
    AS $$
    DECLARE 
        _is_premium BOOLEAN DEFAULT FALSE; 
        comp RECORD; 
        curr_id UUID DEFAULT NULL;
        curr_value DECIMAL(19, 4) DEFAULT NULL;
        curr_type_id UUID DEFAULT NULL;
        curr_name TEXT DEFAULT NULL; 
    BEGIN 
        _is_premium := CASE WHEN _reg_fee IS NOT NULL 
                                THEN TRUE 
                            ELSE FALSE
                    END; 
            
        IF _reg_fee_currency_type_id IS NOT NULL THEN

            SELECT c.id, c.value, ct.id, ct."name" AS name
            INTO curr_id, curr_value, curr_type_id, curr_name 
            FROM currency_exchange_rate c
            JOIN currency_type ct ON ct.id = c.currency_type_id 
            WHERE c.currency_type_id = _reg_fee_currency_type_id;
        END IF;

        RAISE NOTICE 'curr_name %', curr_name; 

        FOR comp IN 
            WITH filtered_cdc AS (
                SELECT cdc.*,
                    cps.is_in_total_cost,
                    cps.calculation_sequence
                FROM cost_domain_component cdc
                JOIN cost_component_type cct ON cct.id = cdc.cost_component_type_id
                JOIN cost_product_strategy cps ON cps.cost_component_type_id = cdc.cost_component_type_id
                WHERE (cct.name != 'registry fee'
                        OR (cct.name = 'registry fee' AND cdc.is_promo = TRUE)
                        OR (cct.name = 'registry fee' AND cdc.is_promo = FALSE AND NOT EXISTS (
                            SELECT 1
                            FROM cost_domain_component cdc_inner
                            WHERE cdc_inner.cost_component_type_id = cdc.cost_component_type_id
                                AND cdc_inner.accreditation_tld_id = cdc.accreditation_tld_id
                                AND cdc_inner.order_type_id = cdc.order_type_id
                                AND cdc_inner.currency_type_id = cdc.currency_type_id
                                AND cdc_inner.is_promo = TRUE
                                AND cdc_inner.validity @> _date
                        )))
                    AND (cdc.order_type_id = cps.order_type_id OR cdc.order_type_id IS NULL)
                    AND cps.order_type_id = _order_type_id
                    AND cdc.accreditation_tld_id = _accreditation_tld_id
                    AND cdc.validity @> _date
            )
            SELECT cdc.id AS cost_domain_component_id,
                cdc.cost_component_type_id,
                cct.name AS cost_component_type,
                _period, 
                cdc.period_type_id,
                CASE
                    WHEN cct.name = 'registry fee' AND NOT _is_premium THEN
                        COALESCE(
                            (SELECT cdc_inner.value
                            FROM mv_cost_domain_component cdc_inner
                            WHERE cdc_inner.cost_component_type_id = cdc.cost_component_type_id
                                AND cdc_inner.accreditation_tld_id = cdc.accreditation_tld_id
                                AND cdc_inner.order_type_id = cdc.order_type_id
                                AND cdc_inner.period = _period
                                AND cdc_inner.currency_type_id = cdc.currency_type_id
                                AND cdc_inner.is_promo = cdc.is_promo),
                            CASE
                                WHEN cdc.is_promo AND cdc.is_promo_applied_to_1_year_only THEN
                                    (cdc.value +  get_nonpromo_cost(cdc.accreditation_tld_id, cdc.order_type_id, _period - 1, cdc.period_type_id))
                                ELSE
                                    cdc.value * _period
                            END
                        )
                    WHEN cct.name = 'icann fee' THEN cdc.value * _period 
                    WHEN cct.name = 'registry fee' AND _is_premium THEN _reg_fee
                    ELSE
                        cdc.value
                END AS value,
                CASE WHEN cct.name = 'registry fee' AND _is_premium 
                    THEN _reg_fee_currency_type_id 
                    ELSE cdc.currency_type_id
                    END currency_type_id,
                CASE WHEN cct.name = 'registry fee' AND _is_premium 
                    THEN curr_name
                    ELSE cer.name 
                    END currency,
                CASE WHEN cct.name = 'registry fee' AND _is_premium 
                    THEN curr_value
                    ELSE cer.value 
                    END currency_exchange_rate,
                cdc.is_promo,
                cdc.is_promo_applied_to_1_year_only,
                cdc.is_rebate, 
                CASE
                    WHEN cct.name = 'registry fee' AND _is_premium THEN TRUE 
                    ELSE FALSE
                END is_premium,
                cct.is_percent,
                cct.is_periodic, 
                cdc.is_in_total_cost, 
                CASE 
                    WHEN cdc.is_promo AND cdc.is_promo_applied_to_1_year_only AND _period > 1
                        THEN cdc.value::INTEGER
                    ELSE NULL::INTEGER
                    END promo_reg_fee,
                CASE 
                    WHEN cdc.is_promo AND cdc.is_promo_applied_to_1_year_only AND _period > 1 
                        THEN get_nonpromo_cost(cdc.accreditation_tld_id, cdc.order_type_id, _period-1 )::INTEGER
                    ELSE NULL::INTEGER
                    END nonpromo_reg_fee,
                cdc.calculation_sequence
            FROM filtered_cdc cdc
            JOIN cost_component_type cct ON cct.id = cdc.cost_component_type_id
            LEFT JOIN mv_currency_exchange_rate cer ON cer.currency_type_id = cdc.currency_type_id 
            ORDER BY cdc.calculation_sequence DESC
        LOOP 

            RETURN QUERY
                        SELECT 
                            comp.cost_domain_component_id,
                            comp.cost_component_type_id,
                            comp.cost_component_type,
                            _period,
                            _period_type_id,
                            comp.value,
                            comp.currency_type_id,
                            comp.currency,
                            comp.currency_exchange_rate,
                            comp.is_promo,
                            comp.is_promo_applied_to_1_year_only,
                            comp.is_rebate, 
                            comp.is_premium,
                            comp.is_percent  ,
                            comp.is_periodic,
                            comp.is_in_total_cost,
                            comp.promo_reg_fee,
                            comp.nonpromo_reg_fee,
                            comp.calculation_sequence;  
        END LOOP; 
    END; 
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION get_total_cost_domain (
        _accreditation_tld_id UUID, 
        _order_type_id UUID, 
        _period INTEGER DEFAULT 1, 
        _period_type_id UUID DEFAULT tc_id_from_name('period_type','year'), 
        _reg_fee INTEGER DEFAULT NULL, 
        _reg_fee_currency_type_id UUID DEFAULT NULL, 
        _date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
    RETURNS TABLE (
        total_value DECIMAL(19, 4),
        currency_type_id UUID, 
        currency TEXT
    ) 
    AS $$
    DECLARE
        total_cost DECIMAL(19, 4) := 0;
        registry_fee_value NUMERIC := 0;
        registry_fee_currency_exchange_rate NUMERIC := 1;
        comp RECORD;
    BEGIN
        FOR comp IN 
            SELECT * FROM get_total_cost_domain_components(
                _accreditation_tld_id, 
                _order_type_id, 
                _period, 
                _period_type_id, 
                _reg_fee, 
                _reg_fee_currency_type_id, 
                _date
            )
        LOOP
            CASE 
                WHEN comp.cost_component_type = 'registry fee' THEN
                    total_cost := total_cost + comp.value * comp.currency_exchange_rate;
                    registry_fee_value := comp.value;
                    registry_fee_currency_exchange_rate := comp.currency_exchange_rate;
                WHEN comp.cost_component_type != 'registry fee' AND comp.is_percent THEN
                    total_cost := total_cost + registry_fee_value * registry_fee_currency_exchange_rate * (comp.value / 100);
                ELSE
                    total_cost := total_cost + comp.value * comp.currency_exchange_rate;
            END CASE;
        END LOOP;

        RETURN QUERY
        SELECT 
            total_cost AS total_value,
            tc_id_from_name('currency_type', 'USD'),
            'USD'; 

    END;
    $$ LANGUAGE plpgsql;

-- db/cost/triggers.ddl 
    
    CREATE OR REPLACE TRIGGER refresh_mv_cost_domain_component_tg
        AFTER INSERT ON cost_domain_component
        FOR EACH ROW
        EXECUTE FUNCTION refresh_mv_cost_domain_component();

    CREATE OR REPLACE TRIGGER refresh_mv_currency_exchange_rate_tg 
        AFTER INSERT ON currency_exchange_rate
        FOR EACH ROW
        EXECUTE FUNCTION refresh_mv_currency_exchange_rate(); 

    CREATE OR REPLACE TRIGGER refresh_mv_order_type_period_type_tg
        AFTER INSERT ON order_type_period_type
        FOR EACH ROW
        EXECUTE FUNCTION refresh_mv_order_type_period_type(); 

-- db/cost/views.ddl 
    DROP MATERIALIZED VIEW IF EXISTS mv_cost_domain_component; 
    CREATE MATERIALIZED VIEW mv_cost_domain_component AS
    WITH latest_cost_domain_component AS (
        SELECT *,
            ROW_NUMBER() OVER (PARTITION BY cost_component_type_id, order_type_id, accreditation_tld_id, is_promo ORDER BY validity DESC, id DESC) AS rn
        FROM cost_domain_component
    )
    SELECT tld.name AS tld_name, 
        cct.name AS cost_component_type, 
        ot.name AS order_type, 
        dcc.value, 
        ct.name AS currency, 
        dcc.is_promo, 
        dcc.is_promo_applied_to_1_year_only, 
        dcc.validity,
        dcc.id,
        dcc.cost_component_type_id,
        dcc.order_type_id,
        dcc.period,
        dcc.currency_type_id,
        dcc.accreditation_tld_id
    FROM latest_cost_domain_component dcc
    JOIN cost_component_type cct ON cct.id = dcc.cost_component_type_id
    JOIN accreditation_tld act ON act.id = dcc.accreditation_tld_id
    JOIN provider_instance_tld pit ON pit.id = act.provider_instance_tld_id
    JOIN tld ON tld.id = pit.tld_id
    LEFT JOIN order_type ot ON ot.id = dcc.order_type_id
    LEFT JOIN currency_type ct ON ct.id = dcc.currency_type_id
    WHERE dcc.rn = 1
    ORDER BY tld.name, 
        CASE
        WHEN is_promo IS TRUE THEN 1
        ELSE 2
        END;

    CREATE UNIQUE INDEX idx_mv_cost_domain_component ON mv_cost_domain_component (id);

    DROP MATERIALIZED VIEW IF EXISTS mv_currency_exchange_rate; 
    CREATE MATERIALIZED VIEW mv_currency_exchange_rate AS -- mv_exchange_rate AS
    WITH latest_exchange_rate AS (
        SELECT *,
            ROW_NUMBER() OVER (PARTITION BY currency_type_id ORDER BY validity DESC) AS rn
        FROM currency_exchange_rate
        WHERE validity @> NOW()
    )
    SELECT ct.name,
            c.value,
            ct.fraction,
            c.validity,
            ct.id AS currency_type_id,
            c.id AS currency_exchange_rate_id,
            ct.descr
    FROM latest_exchange_rate c
    JOIN currency_type ct ON ct.id = c.currency_type_id
    WHERE c.rn = 1;

    CREATE UNIQUE INDEX idx_mv_currency_exchange_rate ON mv_currency_exchange_rate (currency_exchange_rate_id);

    DROP MATERIALIZED VIEW IF EXISTS mv_order_type_period_type; 
    CREATE MATERIALIZED VIEW mv_order_type_period_type AS
        SELECT
        p.name AS product
        ,ot.name AS order_type
        ,u.name AS period_type
        ,p.id AS product_id 
        ,o.order_type_id 
        ,o.period_type_id 
        FROM order_type_period_type o
        JOIN order_type ot ON ot.id = o.order_type_id
        JOIN product p ON ot.product_id = p.id
        JOIN period_type u ON u.id = o.period_type_id
        ORDER BY p.name, ot.name;

    CREATE UNIQUE INDEX idx_mv_order_type_period_type ON mv_order_type_period_type (order_type_id, period_type_id);

    DROP MATERIALIZED VIEW IF EXISTS mv_cost_product_strategy; 
    CREATE MATERIALIZED VIEW mv_cost_product_strategy AS
        SELECT 
            vot.name AS order_type
            ,vot.product_name
            ,cct.name AS cost_component_type
            ,cps.calculation_sequence
            ,cct.is_periodic
            ,cct.is_percent
            ,cps.is_in_total_cost
            ,cps.id AS cost_product_strategy_id
            ,cps.order_type_id
            ,cps.cost_component_type_id
        FROM cost_product_strategy cps
        JOIN v_order_type vot ON vot.id = cps.order_type_id
        JOIN cost_component_type cct ON cct.id = cps.cost_component_type_id
        ORDER BY vot.name, cps.calculation_sequence DESC;

    CREATE UNIQUE INDEX idx_mv_cost_product_strategy ON mv_cost_product_strategy (cost_product_strategy_id);