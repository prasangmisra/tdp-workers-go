-- db/price/schema.ddl
    CREATE TABLE  IF NOT EXISTS promo_type (
        id 			UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        "name" 		TEXT NOT NULL,
        descr 		TEXT NOT NULL,
        UNIQUE ("name")
    );
    CREATE INDEX idx_promo_type_name ON  promo_type(name);

    CREATE TABLE  IF NOT EXISTS price_type (
        id 				UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        "name" 			TEXT NOT NULL,
        descr 			TEXT NOT NULL,
        overrides 		UUID[] NULL,
        level 			INTEGER NOT NULL DEFAULT 0, 
        UNIQUE ("name")
    );
    CREATE INDEX idx_price_type_id ON price_type(id);
    CREATE INDEX idx_price_type_name ON  price_type(name);

    CREATE TABLE IF NOT EXISTS  product_cost_range (
        id 			UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        product_id 	UUID NOT NULL REFERENCES product,
        value 		NUMRANGE NOT NULL,
        UNIQUE(product_id, value)
    );
    CREATE INDEX idx_product_cost_range_product_id ON  product_cost_range(product_id);

    CREATE TABLE IF NOT EXISTS  domain_premium_margin (
        id 								UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        price_type_id 					UUID NOT NULL REFERENCES price_type, 
        product_cost_range_id			UUID NOT NULL REFERENCES product_cost_range, 
        tenant_customer_id 				UUID REFERENCES tenant_customer,
        accreditation_tld_id			UUID REFERENCES accreditation_tld, 
        value 							REAL, 
        start_date						TIMESTAMPTZ NOT NULL
    ) INHERITS (class.audit,class.soft_delete);

    CREATE UNIQUE INDEX unique_domain_premium_margin
    ON  domain_premium_margin (
        price_type_id, 
        product_cost_range_id,
        null_to_value(tenant_customer_id),
        null_to_value(accreditation_tld_id),
        start_date
    );
    CREATE INDEX idx_domain_premium_margin_product_cost_range_id ON  domain_premium_margin(product_cost_range_id);
    CREATE INDEX idx_domain_premium_margin_tenant_customer_id ON  domain_premium_margin(tenant_customer_id);
    CREATE INDEX idx_domain_premium_margin_accreditation_tld_id ON  domain_premium_margin(accreditation_tld_id);
    CREATE INDEX idx_domain_premium_margin_price_type_id ON  domain_premium_margin(price_type_id);

    CREATE TABLE IF NOT EXISTS  product_tier_type(
        id 			UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        product_id	UUID NOT NULL REFERENCES product,
        "name" 		TEXT NOT NULL,
        UNIQUE (name, product_id)
    );
    CREATE INDEX idx_product_tier_type_name ON  product_tier_type(name);
    CREATE INDEX idx_product_tier_type_product_id ON  product_tier_type(product_id);

    CREATE TABLE IF NOT EXISTS  product_customer_tier(
        id 						UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        tenant_customer_id 		UUID NOT NULL REFERENCES tenant_customer, 
        product_tier_type_id 	UUID NOT NULL REFERENCES product_tier_type,
        start_date				TIMESTAMPTZ NOT NULL,
        UNIQUE(tenant_customer_id, 
            product_tier_type_id,
            start_date)
    ) INHERITS (class.audit,class.soft_delete);

    CREATE INDEX idx_product_customer_tier_tenant_customer_id ON  product_customer_tier(tenant_customer_id);
    CREATE INDEX idx_product_customer_tier_product_tier_type_id ON  product_customer_tier(product_tier_type_id);

    CREATE TABLE IF NOT EXISTS  product_price_strategy(
        id 						UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        product_id				UUID NOT NULL REFERENCES product, 
        price_type_id			UUID NOT NULL REFERENCES price_type, 
        level					INTEGER NOT NULL, 	
        iteration_order			INTEGER NOT NULL,
        UNIQUE(product_id, price_type_id)
    ) INHERITS (class.audit, class.soft_delete);

    CREATE TABLE IF NOT EXISTS  domain_price_tier(
        id 												UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        tenant_id										UUID NOT NULL REFERENCES tenant,
        price_type_id									UUID NOT NULL REFERENCES price_type, 
        order_type_id									UUID NOT NULL REFERENCES order_type,
        product_tier_type_id 							UUID NOT NULL REFERENCES product_tier_type,
        value 											INTEGER NOT NULL,
        period 											INTEGER NOT NULL DEFAULT 1,
        period_type_id									UUID NOT NULL REFERENCES period_type, 	
        currency_type_id 								UUID NOT NULL REFERENCES currency_type,				
        validity										TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
        accreditation_tld_id							UUID NOT NULL REFERENCES accreditation_tld,
        EXCLUDE USING gist (tenant_id WITH =,
            price_type_id WITH =,
            order_type_id WITH =,
            product_tier_type_id WITH =,
            period WITH =,
            period_type_id WITH =,
            currency_type_id WITH =,
            accreditation_tld_id WITH =,
            validity WITH &&)
    ) INHERITS (class.audit);
    CREATE INDEX idx_domain_price_tier_tenant_id ON  domain_price_tier(tenant_id);
    CREATE INDEX idx_domain_price_tier_price_type_id ON  domain_price_tier(price_type_id);
    CREATE INDEX idx_domain_price_tier_order_type_id ON  domain_price_tier(order_type_id);
    CREATE INDEX idx_domain_price_tier_product_tier_type_id ON  domain_price_tier(product_tier_type_id);
    CREATE INDEX idx_domain_price_tier_currency_type_id ON  domain_price_tier(currency_type_id);
    CREATE INDEX idx_domain_price_tier_accreditation_tld_id ON  domain_price_tier(accreditation_tld_id);
    CREATE INDEX idx_domain_price_tier_period_type_id ON  domain_price_tier(period_type_id);

    CREATE TABLE IF NOT EXISTS  domain_price_custom(
        id 												UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        tenant_customer_id 								UUID NOT NULL REFERENCES tenant_customer,
        price_type_id									UUID NOT NULL REFERENCES price_type, 
        order_type_id									UUID NOT NULL REFERENCES order_type,
        accreditation_tld_id							UUID NOT NULL REFERENCES accreditation_tld,
        value 											INTEGER NOT NULL,
        period 											INTEGER NOT NULL DEFAULT 1,
        period_type_id 									UUID NOT NULL REFERENCES period_type, 
        currency_type_id 								UUID NOT NULL REFERENCES currency_type,
        validity										TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
        is_promo_cost_supported							BOOLEAN DEFAULT NULL,
        EXCLUDE USING gist (
            tenant_customer_id WITH =,
            price_type_id WITH =,
            order_type_id WITH =,
            period WITH =,
            period_type_id WITH =,
            currency_type_id WITH =,
            accreditation_tld_id WITH =,
            validity WITH &&
        )
    ) INHERITS (class.audit);

    CREATE INDEX idx_domain_price_custom_tenant_customer_id ON  domain_price_custom(tenant_customer_id);
    CREATE INDEX idx_domain_price_custom_price_type_id ON  domain_price_custom(price_type_id);
    CREATE INDEX idx_domain_price_custom_order_type_id ON  domain_price_custom(order_type_id);
    CREATE INDEX idx_domain_price_custom_currency_type_id ON  domain_price_custom(currency_type_id);
    CREATE INDEX idx_domain_price_custom_accreditation_tld_id ON  domain_price_custom(accreditation_tld_id);
    CREATE INDEX idx_domain_price_custom_period_type_id ON  domain_price_custom(period_type_id);

    CREATE TABLE IF NOT EXISTS  domain_price_tenant_promo(
        id 												UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        tenant_id										UUID NOT NULL REFERENCES tenant,
        price_type_id									UUID NOT NULL REFERENCES price_type, 
        order_type_id									UUID NOT NULL REFERENCES order_type,
        promo_type_id									UUID REFERENCES promo_type, 
        accreditation_tld_id							UUID NOT NULL REFERENCES accreditation_tld,
        value 											INTEGER NOT NULL,
        period 											INTEGER NOT NULL DEFAULT 1,
        period_type_id 									UUID NOT NULL REFERENCES period_type, 
        currency_type_id 								UUID REFERENCES currency_type,
        validity										TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
        is_promo_applied_to_1_year_registrations_only 	BOOLEAN DEFAULT FALSE,
        is_rebate 										BOOLEAN DEFAULT FALSE,
        EXCLUDE USING gist (tenant_id WITH =,
            price_type_id WITH =,
            order_type_id WITH =,
            promo_type_id WITH =,
            accreditation_tld_id WITH =,
            period WITH =,
            period_type_id WITH =, 
            currency_type_id WITH =,
            validity WITH &&)
    ) INHERITS (class.audit);

    CREATE INDEX idx_domain_price_tenant_promo_tenant_id ON  domain_price_tenant_promo(tenant_id);
    CREATE INDEX idx_domain_price_tenant_promo_price_type_id ON  domain_price_tenant_promo(price_type_id);
    CREATE INDEX idx_domain_price_tenant_promo_order_type_id ON  domain_price_tenant_promo(order_type_id);
    CREATE INDEX idx_domain_price_tenant_promo_promo_type_id ON  domain_price_tenant_promo(promo_type_id);
    CREATE INDEX idx_domain_price_tenant_promo_accreditation_tld_id ON  domain_price_tenant_promo(accreditation_tld_id);
    CREATE INDEX idx_domain_price_tenant_promo_period_type_id ON  domain_price_tenant_promo(period_type_id);
    CREATE INDEX idx_domain_price_tenant_promo_currency_type_id ON  domain_price_tenant_promo(currency_type_id);

    CREATE TABLE IF NOT EXISTS  domain_price_customer_promo(
        id 												UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        tenant_customer_id 								UUID REFERENCES tenant_customer,
        price_type_id									UUID NOT NULL REFERENCES price_type, 
        promo_type_id									UUID REFERENCES promo_type, 
        order_type_id									UUID NOT NULL REFERENCES order_type,
        accreditation_tld_id							UUID NOT NULL REFERENCES accreditation_tld,
        value 											INTEGER NOT NULL,
        period 											INTEGER NOT NULL DEFAULT 1,
        period_type_id 									UUID NOT NULL REFERENCES period_type, 
        currency_type_id 								UUID REFERENCES currency_type,
        validity										TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
        is_promo_applied_to_1_year_registrations_only 	BOOLEAN DEFAULT FALSE,
        is_rebate 										BOOLEAN DEFAULT FALSE,
        EXCLUDE USING gist (tenant_customer_id WITH =,
            price_type_id WITH =,
            order_type_id WITH =,
            promo_type_id WITH =,
            accreditation_tld_id WITH =,
            period WITH =,
            period_type_id WITH =, 
            currency_type_id WITH =,
            validity WITH &&)
    ) INHERITS (class.audit);
    CREATE INDEX idx_domain_price_customer_promo_tenant_customer_id ON  domain_price_customer_promo(tenant_customer_id);
    CREATE INDEX idx_domain_price_customer_promo_price_type_id ON  domain_price_customer_promo(price_type_id);
    CREATE INDEX idx_domain_price_customer_promo_order_type_id ON  domain_price_customer_promo(order_type_id);
    CREATE INDEX idx_domain_price_customer_promo_promo_type_id ON  domain_price_customer_promo(promo_type_id);
    CREATE INDEX idx_domain_price_customer_promo_accreditation_tld_id ON  domain_price_customer_promo(accreditation_tld_id);
    CREATE INDEX idx_domain_price_customer_promo_period_type_id ON  domain_price_customer_promo(period_type_id);
    CREATE INDEX idx_domain_price_customer_promo_currency_type_id ON  domain_price_customer_promo(currency_type_id);

    CREATE TABLE IF NOT EXISTS  repeating_charge_type (
        id 			UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        "name" 		TEXT NOT NULL,
        descr 		TEXT NOT NULL,
        UNIQUE ("name")
    );
    CREATE INDEX idx_repeating_charge_type_name ON  repeating_charge_type(name);

    CREATE TABLE IF NOT EXISTS  domain_price_repeating_charge(
        id 										UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
        repeating_charge_type_id 				UUID NOT NULL REFERENCES repeating_charge_type, 
        product_id								UUID NOT NULL REFERENCES product, 
        price_type_id							UUID NOT NULL REFERENCES price_type, 
        tenant_customer_id 						UUID NOT NULL REFERENCES tenant_customer,
        value 									INTEGER,
        period 									INTEGER NOT NULL DEFAULT 1, 
        period_type_id 							UUID NOT NULL REFERENCES period_type, 
        currency_type_id 						UUID NOT NULL REFERENCES currency_type,
        validity								TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
        EXCLUDE USING gist (
            repeating_charge_type_id WITH =,
            product_id WITH =,
            price_type_id WITH =,
            tenant_customer_id WITH =,
            period WITH =,
            period_type_id WITH =, 
            currency_type_id WITH =,
            validity WITH &&)
    ) INHERITS (class.audit);
    CREATE INDEX idx_domain_price_repeating_charge_repeating_charge_type_id ON  domain_price_repeating_charge(repeating_charge_type_id);
    CREATE INDEX idx_domain_price_repeating_charge_product_id ON  domain_price_repeating_charge(product_id);
    CREATE INDEX idx_domain_price_repeating_charge_price_type_id ON  domain_price_repeating_charge(price_type_id);
    CREATE INDEX idx_domain_price_repeating_charge_tenant_customer_id ON  domain_price_repeating_charge(tenant_customer_id);
    CREATE INDEX idx_domain_price_repeating_charge_period_type_id ON  domain_price_repeating_charge(period_type_id);
    CREATE INDEX idx_domain_price_repeating_charge_currency_type_id ON  domain_price_repeating_charge(currency_type_id);

-- db/price/views.ddl 
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

-- db/price/stored-procedures/helpers.ddl 
    CREATE OR REPLACE FUNCTION refresh_mv_product_customer_tier()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_product_customer_tier;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_product_price_strategy()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_product_price_strategy;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_domain_price_tier()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_domain_price_tier;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_domain_premium_margin()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_domain_premium_margin;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_domain_price_custom()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_domain_price_custom;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_domain_price_tenant_promo()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_domain_price_tenant_promo;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION refresh_mv_domain_price_customer_promo()
    RETURNS trigger AS $$
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_domain_price_customer_promo;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;

-- db/price/stored-procedures/price_calculations.ddl 

    CREATE OR REPLACE FUNCTION roundup(_amount DECIMAL(19, 5), _roundup_to INTEGER)  
    RETURNS INTEGER
    AS $$
    BEGIN
        RETURN (CEIL(_amount / _roundup_to) * _roundup_to)::INTEGER;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION convert_currency_with_detail ( _amount DECIMAL(19, 5),
                                                            _from_currency_type_id UUID,
                                                            _to_currency_type_id UUID)
    RETURNS TABLE ( value DECIMAL(19, 5),
                    to_currency TEXT,
                    to_currency_type_id UUID,
                    to_exchange_rate DECIMAL(19, 5), 
                    to_exchange_rate_id UUID,
                    from_currency TEXT, 
                    from_currency_type_id UUID,
                    from_exchange_rate DECIMAL(19, 5), 
                    from_exchange_rate_id UUID)
    AS $$
    BEGIN 
        RETURN QUERY
            WITH conversion1 AS (
                SELECT from_.value, from_.name, from_.currency_exchange_rate_id, from_.currency_type_id
                FROM mv_currency_exchange_rate from_
                WHERE from_.currency_type_id = _from_currency_type_id
            ),conversion2 AS (
                SELECT to_.value, to_.name, to_.currency_exchange_rate_id, to_.currency_type_id
                FROM mv_currency_exchange_rate to_
                WHERE to_.currency_type_id = _to_currency_type_id
            )   SELECT 
                    _amount * conversion1.value / conversion2.value AS value, 
                    conversion2.name AS to_currency,
                    conversion2.currency_type_id AS to_currency_type_id,
                    conversion2.value AS to_exchange_rate,
                    conversion2.currency_exchange_rate_id AS to_exchange_rate_id, 
                    conversion1.name AS from_currency,
                    conversion1.currency_type_id AS from_currency_type_id,
                    conversion1.value AS from_exchange_rate, 
                    conversion1.currency_exchange_rate_id AS from_exchange_rate_id      
                FROM 
                    conversion1, conversion2;
    END;
    $$ LANGUAGE plpgsql;
    
    CREATE OR REPLACE FUNCTION signup_for_promotion( _tenant_customer_id UUID, _domain_price_tenant_promo_id UUID)
    RETURNS VOID 
    AS $$
    BEGIN
        INSERT INTO domain_price_customer_promo (
            tenant_customer_id,
            price_type_id,
            promo_type_id,
            order_type_id,
            accreditation_tld_id,
            value,
            PERIOD,
            period_type_id,
            currency_type_id,
            validity,
            is_promo_applied_to_1_year_registrations_only)
            SELECT 
                _tenant_customer_id,
                dptp.price_type_id,
                dptp.promo_type_id,
                dptp.order_type_id,
                dptp.accreditation_tld_id,
                dptp.value,
                dptp.PERIOD,
                dptp.period_type_id,  
                dptp.currency_type_id,
                dptp.validity,
                dptp.is_promo_applied_to_1_year_registrations_only
            FROM domain_price_tenant_promo dptp
            WHERE dptp.id = _domain_price_tenant_promo_id; 
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION show_domain_price_tier(
        _accreditation_tld_id UUID, 
        _order_type_id UUID, 
        _tenant_customer_id UUID DEFAULT NULL, 
        _period INTEGER DEFAULT 1, 
        _period_type_id UUID DEFAULT tc_id_from_name('period_type','year'),
        _date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
    RETURNS TABLE (essential_tier INTEGER, advanced_tier INTEGER, premium_tier INTEGER, enterprise_tier INTEGER, 
        currency TEXT, currency_type_id UUID) 
    AS $$ 
    BEGIN
        RETURN QUERY
            SELECT DISTINCT 
            MAX(CASE WHEN dpt.period = _period AND ptt.name = 'essential' THEN dpt.value 
                WHEN dpt.period = 1 AND ptt.name = 'essential' THEN dpt.value * _period 
                ELSE NULL END) AS essential_tier, 
            MAX(CASE WHEN dpt.period = _period AND ptt.name = 'advanced' THEN dpt.value 
                WHEN dpt.period = 1 AND ptt.name = 'advanced' THEN dpt.value * _period                 
                ELSE NULL END) AS advanced_tier, 
            MAX(CASE WHEN dpt.PERIOD = _period AND ptt.name = 'premium' THEN dpt.value 
                WHEN dpt.period = 1 AND ptt.name = 'premium' THEN dpt.value * _period                  
                ELSE NULL END) AS premium_tier, 
            MAX(CASE WHEN dpt.PERIOD = _period AND ptt.name = 'enterprise' THEN dpt.value  
                WHEN dpt.period = 1 AND ptt.name = 'enterprise' THEN dpt.value * _period   
                ELSE NULL END) AS enterprise_tier, 
            MAX(ct.name) AS currency,
            dpt.currency_type_id
            FROM domain_price_tier dpt
            LEFT JOIN product_customer_tier pct ON pct.product_tier_type_id = dpt.product_tier_type_id 
            JOIN product_tier_type ptt ON ptt.id = pct.product_tier_type_id 
            JOIN currency_type ct ON ct.id = dpt.currency_type_id
            JOIN accreditation_tld act ON act.id = dpt.accreditation_tld_id
            JOIN accreditation a ON a.id = act.accreditation_id
            WHERE dpt.price_type_id = tc_id_from_name('price_type','tier')
                AND dpt.accreditation_tld_id = _accreditation_tld_id
                AND dpt.order_type_id = _order_type_id
                AND dpt.validity @> _date
                AND (dpt.period = _period OR dpt.period = 1)
                AND  CASE WHEN _tenant_customer_id IS NOT NULL 
                    THEN pct.tenant_customer_id = _tenant_customer_id
                    ELSE dpt.tenant_id = a.tenant_id 
                END
            GROUP BY dpt.currency_type_id; 

    END;
    $$ LANGUAGE plpgsql;

    CREATE TYPE price_data_type AS (
        total_price DECIMAL(19, 4), -- INTEGER,
        currency TEXT,
        currency_exchange_rate DECIMAL(19, 4),
        price_type TEXT,
        price_type_id UUID,
        price_detail JSONB
    );

    CREATE OR REPLACE FUNCTION get_domain_price_tier(
        _accreditation_tld_id UUID, 
        _order_type_id UUID,
        _tenant_customer_id UUID, 
        _period INTEGER DEFAULT 1, 
        _period_type_id UUID DEFAULT tc_id_from_name('period_type','year'),
        _date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
    RETURNS SETOF price_data_type 
    AS $$
    BEGIN   
        RETURN QUERY
            WITH tier_price AS (
                SELECT 
                    COALESCE(s.essential_tier,s.advanced_tier,s.premium_tier ,s.enterprise_tier) AS value,
                    COALESCE(
                        CASE WHEN s.essential_tier IS NOT NULL THEN 'essential_tier'
                            WHEN s.advanced_tier IS NOT NULL THEN 'advanced_tier'
                            WHEN s.premium_tier IS NOT NULL THEN 'premium_tier'
                            WHEN s.enterprise_tier IS NOT NULL THEN 'enterprise_tier'
                        END, 'unknown') AS tier_name,
                    s.currency, 
                    s.currency_type_id
                FROM show_domain_price_tier(
                        _tenant_customer_id:= _tenant_customer_id, 
                        _accreditation_tld_id:= _accreditation_tld_id ,
                        _order_type_id:= _order_type_id,
                        _period:= _period, 
                        _date:= _date  
                    ) s
            ), customer_cur AS ( 
                SELECT 
                    tier_price.value AS tier_price_value,
                    tier_price.currency AS tier_price_currency,
                    p.from_exchange_rate,
                    tier_price.tier_name AS tier_name,
                    p.value AS to_value, 
                    p.to_currency,
                    p.to_exchange_rate,
                    tier_price.currency_type_id AS from_currency_type_id,
                    p.to_currency_type_id,
                    p.to_exchange_rate_id
                FROM tier_price
                JOIN convert_currency_with_detail (
                            _amount:= tier_price.value, 
                            _from_currency_type_id:= tier_price.currency_type_id, 
                            _to_currency_type_id:= tc_id_from_name('currency_type', 
                                (SELECT get_finance_setting( 
                                    p_name:= 'tenant_customer.provider_instance_tld.specific_currency',
                                    p_tenant_customer_id:= _tenant_customer_id,
                                    p_provider_instance_tld_id:= acc.provider_instance_tld_id)
                                FROM accreditation_tld acc 
                                WHERE acc.id = _accreditation_tld_id))
                ) p ON TRUE
            ), roundup AS(
                SELECT CAST(get_finance_setting('general.round_up_non_premium') AS INTEGER) AS value
            )   SELECT  
                    -- roundup( customer_cur.to_value, roundup.value)::DECIMAL(19, 4) AS total_price,
                    customer_cur.to_value::DECIMAL(19, 4) AS total_price,
                    customer_cur.to_currency AS currency,
                    customer_cur.to_exchange_rate::DECIMAL(19, 4) AS currency_exchange_rate, 
                    'tier', 
                    tc_id_from_name('price_type','tier'), 
                    jsonb_build_object(
                        'tier_price', 					customer_cur.tier_price_value, 
                        'tier_price_currency', 			customer_cur.tier_price_currency,
                        'from_exchange_rate',			customer_cur.from_exchange_rate,
                        'tier_type', 					customer_cur.tier_name, 
                        'customer_currency', 			customer_cur.to_currency,
                        'to_exchange_rate',			    customer_cur.to_exchange_rate,
                        'from_currency_type_id',		customer_cur.from_currency_type_id, 
                        'to_currency_type_id',		    customer_cur.to_currency_type_id,
                        'to_exchange_rate_id',	        customer_cur.to_exchange_rate_id
                        --'general.round_up_non_premium',	roundup.value
                    ) AS price_detail
                FROM customer_cur, roundup;  
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION get_domain_price_custom(
        _accreditation_tld_id UUID, 
        _order_type_id UUID,
        _tenant_customer_id UUID, 
        _period INTEGER DEFAULT 1, 
        _period_type_id UUID DEFAULT tc_id_from_name('period_type','year'),
        _date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
    RETURNS SETOF price_data_type
    AS $$
    BEGIN

        RETURN QUERY
            WITH "cost" AS (
                SELECT * 
                FROM get_total_cost_domain(
                    _accreditation_tld_id := _accreditation_tld_id,
                    _order_type_id := _order_type_id,  
                    _period := _period,
                    _date := _date)	 
            ), domain_price_custom_value AS(                                
                SELECT *,
                    CASE WHEN dpc.PERIOD = 1 THEN dpc.value * _period
                        ELSE dpc.value
                    END price
                FROM mv_domain_price_custom dpc
                WHERE dpc.tenant_customer_id = _tenant_customer_id
                    AND dpc.accreditation_tld_id = _accreditation_tld_id
                    AND dpc.order_type_id = _order_type_id
                    AND (dpc.PERIOD = _period OR dpc.period = 1)
                    AND dpc.validity @> _date
            ), custom_currency AS (                                        
                SELECT get_finance_setting( 
                        p_name:= 'tenant_customer.provider_instance_tld.specific_currency',
                        p_tenant_customer_id:= _tenant_customer_id,
                        p_provider_instance_tld_id:= acc.provider_instance_tld_id) as value
                    FROM accreditation_tld acc 
                    WHERE acc.id = _accreditation_tld_id
            ), custom_price_conversion AS (                                   
                SELECT 
                    p.from_exchange_rate,
                    p.from_currency,
                    p.from_currency_type_id, 
                    p.value, 
                    p.to_currency,
                    p.to_exchange_rate,
                    p.to_currency_type_id,
                    p.to_exchange_rate_id
                FROM domain_price_custom_value,  custom_currency
                JOIN convert_currency_with_detail (
                            _amount:= domain_price_custom_value.price, 
                            _from_currency_type_id:= domain_price_custom_value.currency_type_id, 
                            _to_currency_type_id:= tc_id_from_name('currency_type', custom_currency.value)
                ) p ON TRUE
            ), cost_conversion AS (
                SELECT *
                FROM "cost" ,  custom_currency
                JOIN convert_currency_with_detail (
                                _amount:= "cost".total_value, 
                                _from_currency_type_id:= "cost".currency_type_id, 
                                _to_currency_type_id:= tc_id_from_name('currency_type', custom_currency.value)
                    ) p ON TRUE
            ), total_price AS(
                SELECT 
                    CASE WHEN domain_price_custom_value.price_type = 'custom - cost+' 
                        THEN custom_price_conversion.value + cost_conversion.total_value  
                        ELSE custom_price_conversion.value
                    END value
                FROM custom_price_conversion, cost_conversion, domain_price_custom_value
            ), json_build AS(
                SELECT 
                jsonb_build_object(
                    'price_type',							domain_price_custom_value.price_type,
                    'custom_price_value', 					domain_price_custom_value.price, 
                    'custom_price_currency', 				custom_price_conversion.from_currency, 
                    'custom_currency_type_id',				custom_price_conversion.from_currency_type_id, 
                    'custom_price_exchange_rate',			custom_price_conversion.from_exchange_rate,    
                    'to_currency', 						    custom_price_conversion.to_currency,
                    'to_currency_type_id',				    custom_price_conversion.to_currency_type_id,
                    'to_exchange_rate',					    custom_price_conversion.to_exchange_rate
                ) AS main
                FROM total_price, domain_price_custom_value, custom_price_conversion
            ) SELECT  
                total_price.value::DECIMAL(19, 4) AS total_price,
                custom_price_conversion.to_currency AS currency,
                custom_price_conversion.to_exchange_rate::DECIMAL(19, 4) AS currency_exchange_rate, 
                domain_price_custom_value.price_type, 
                domain_price_custom_value.price_type_id, 
                CASE WHEN domain_price_custom_value.price_type = 'custom' 
                    THEN json_build.main
                    ELSE 
                        json_build.main || jsonb_build_object(
                            'cost_value',							"cost".total_value,
                            'cost_currency',						"cost".currency,
                            'cost_currency_type_id',				"cost".currency_type_id, 
                            'cost_exchange_rate',				    cost_conversion.from_exchange_rate
                        )
                    END price_detail
            FROM total_price, domain_price_custom_value, custom_price_conversion, "cost", json_build, cost_conversion  ; 
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION get_domain_price_premium (
        _accreditation_tld_id UUID, 
        _tenant_customer_id UUID, 
        _reg_fee INTEGER DEFAULT NULL, 
        _reg_currency TEXT DEFAULT NULL)
    RETURNS SETOF price_data_type
    AS $$
    BEGIN

        IF _reg_fee IS NULL THEN
            RETURN QUERY
                SELECT 
                NULL::DECIMAL(19, 4) AS total_price, 
                NULL::TEXT AS currency,
                NULL::DECIMAL(19, 4) AS currency_exchange_rate,
                NULL::TEXT AS price_type,
                NULL::UUID AS price_type_id,
                '{}'::JSONB AS price_detail
                WHERE FALSE; -- Ensure the function returns an empty result set

                RETURN;  -- Stop function execution after RETURN QUERY
        END IF;

        RETURN QUERY
        WITH margin_cap AS (
            SELECT get_finance_setting AS value 
            FROM get_finance_setting('general.margin_cap')
        ), premium_margin AS (
            SELECT 
                dpm.price_type,
                dpm.tld,
                dpm.cost_range,
                dpm.tenant_name,
                dpm.customer_name,
                dpm.value,
                dpm.start_date,
                dpm.id,
                dpm.price_type_id,
                dpm.product_cost_range_id,
                dpm.tenant_customer_id,
                dpm.accreditation_tld_id
            FROM mv_domain_premium_margin dpm
            JOIN mv_product_price_strategy pps ON pps.price_type_id = dpm.price_type_id
            WHERE dpm.cost_range  @> _reg_fee::NUMERIC
                AND ((dpm.tenant_customer_id = _tenant_customer_id 
                        AND dpm.accreditation_tld_id =  _accreditation_tld_id)
                    OR (dpm.tenant_customer_id IS NULL 
                        AND dpm.accreditation_tld_id IS NULL ))
                AND pps.product_id = tc_id_from_name ('product', 'domain')
            ORDER BY pps."level" DESC
            LIMIT 1
        ), regfee_usd AS (
            SELECT 
                p.value,
                p.value * premium_margin.value / 100 AS margin,
                p.value * (1+ premium_margin.value / 100 ) AS total_price_usd,
                p.to_currency,
                p.to_currency_type_id,
                p.to_exchange_rate, 
                p.to_exchange_rate_id,
                p.from_currency, 
                p.from_currency_type_id,
                p.from_exchange_rate,
                p.from_exchange_rate_id
            FROM convert_currency_with_detail (
                                _amount:= _reg_fee, 
                                _from_currency_type_id:= tc_id_from_name ('currency_type', _reg_currency),  
                                _to_currency_type_id:= tc_id_from_name ('currency_type', 'USD')
                ) p  
            JOIN premium_margin ON TRUE
        ), roundup AS(
                SELECT CAST(get_finance_setting('general.round_up_premium') AS INTEGER) AS value
        ), total_price_usd AS(
            SELECT 
            CASE WHEN regfee_usd.margin >=  margin_cap.value::INTEGER THEN regfee_usd.value + margin_cap.value::INTEGER 
                ELSE regfee_usd.total_price_usd
                END value 
            FROM regfee_usd, margin_cap     
        )   SELECT 
                roundup( p.value, 
                    roundup.value)::DECIMAL(19, 4) AS total_price,
                p.to_currency AS currency,
                p.to_exchange_rate::DECIMAL(19, 4) AS currency_exchange_rate,
                premium_margin.price_type,
                premium_margin.price_type_id,
                jsonb_build_object(
                        'price_type',							    premium_margin.price_type,
                        'premium_registry_fee',                     _reg_fee, 
                        'registry_fee_cur',                         _reg_currency, 
                        'registry_fee_currency_type_id',            regfee_usd.from_currency_type_id,  
                        'registry_fee_exchange_rate',               regfee_usd.from_exchange_rate,
                        'registry_fee_exchange_rate_id',            regfee_usd.from_exchange_rate_id, 
                        'premium_margin',                           premium_margin.value, 
                        'to_currency', 						    p.to_currency,
                        'to_currency_type_id',				    p.to_currency_type_id,
                        'to_exchange_rate',					    p.to_exchange_rate,
                        'to_exchange_rate_id',				    p.to_exchange_rate_id,
                        'general.round_up_premium',			        roundup.value,
                        'general.margin_cap',                       margin_cap.value
                ) AS price_detail
            FROM roundup, premium_margin, total_price_usd, margin_cap, regfee_usd
            JOIN convert_currency_with_detail (
                                    _amount:= total_price_usd.value::DECIMAL(19, 5), 
                                    _from_currency_type_id:= tc_id_from_name ('currency_type', 'USD'),
                                    _to_currency_type_id:= tc_id_from_name('currency_type', 
                                        (SELECT get_finance_setting( 
                                            p_name:= 'tenant_customer.provider_instance_tld.specific_currency',
                                            p_tenant_customer_id:= _tenant_customer_id,
                                            p_provider_instance_tld_id:= acc.provider_instance_tld_id)
                                        FROM accreditation_tld acc 
                                        WHERE acc.id = _accreditation_tld_id))
            ) p ON TRUE; 

    END;
    $$ LANGUAGE plpgsql;


    CREATE OR REPLACE FUNCTION get_domain_price_promo (
        _accreditation_tld_id UUID, 
        _order_type_id UUID,
        _tenant_customer_id UUID, 
        _period INTEGER DEFAULT 1,
        _period_type_id UUID DEFAULT tc_id_from_name('period_type','year'),
        _date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
    RETURNS SETOF price_data_type
    AS $$
    BEGIN 

        RETURN QUERY
        WITH tier_price AS (               
            SELECT *
            FROM get_domain_price_tier(_tenant_customer_id:=  _tenant_customer_id,
                _accreditation_tld_id:= _accreditation_tld_id,
                _order_type_id:= _order_type_id,
                _period:= _period - 1,
                _date:= _date)
        ), custom_currency AS (                 
                SELECT get_finance_setting( 
                        p_name:= 'tenant_customer.provider_instance_tld.specific_currency',
                        p_tenant_customer_id:= _tenant_customer_id,
                        p_provider_instance_tld_id:= acc.provider_instance_tld_id) as value
                    FROM accreditation_tld acc 
                    WHERE acc.id = _accreditation_tld_id
        ), tier_price_custom_currency AS (        
            SELECT p.*
            FROM tier_price, custom_currency
            JOIN convert_currency_with_detail (
                                _amount:= tier_price.total_price, 
                                _from_currency_type_id:= tc_id_from_name('currency_type', tier_price.currency),
                                _to_currency_type_id:= tc_id_from_name('currency_type', custom_currency.value)) p ON TRUE 
        ), _tenant AS (
            SELECT tc.tenant_id AS id 
            FROM v_tenant_customer tc 
            WHERE tc.id = _tenant_customer_id 
        ), promo_customer AS (     
            SELECT 
                p.price_type_id,
                p.promo_type_id, 
                p.value,
                p.currency_type_id,
                p.is_promo_applied_to_1_year_registrations_only,
                p.is_rebate,
                p.period, 
                pps.LEVEL,
                p.price_type
            FROM mv_domain_price_customer_promo p
            JOIN product_price_strategy pps ON pps.price_type_id = p.price_type_id
                WHERE p.order_type_id = _order_type_id
                    AND p.accreditation_tld_id = _accreditation_tld_id
                    AND p.tenant_customer_id = _tenant_customer_id
                    AND (p.period = _period
                        OR p.period= 1) 
                    AND p.period_type_id = _period_type_id
                    AND p.validity @> _date 
        ), promo_tenant AS (        
            SELECT  
                p.price_type_id,
                p.promo_type_id,
                p.value,
                p.currency_type_id,
                p.is_promo_applied_to_1_year_registrations_only,
                p.is_rebate,
                p.period, 
                pps.LEVEL, 
                p.price_type
            FROM mv_domain_price_tenant_promo p 
            JOIN _tenant ON TRUE 
            JOIN product_price_strategy pps ON pps.price_type_id = p.price_type_id
            WHERE p.price_type = 'promo - all'
            AND p.order_type_id = _order_type_id
            AND p.accreditation_tld_id = _accreditation_tld_id
            AND p.tenant_id = _tenant.id 
            AND (p.period = _period
                        OR p.period = 1) 
            AND p.period_type_id = _period_type_id
            AND p.validity @> _date
        ), roundup AS (
                    SELECT CAST(get_finance_setting('general.round_up_non_premium') AS INTEGER) AS value 	 
        ), promo_select AS (
            SELECT 
            *
            FROM promo_customer

            UNION 

            SELECT 
            *
            FROM promo_tenant
            ORDER BY "level" DESC 
            LIMIT 1
        ), promo_select_custom_currency AS (
            SELECT p.*
            FROM promo_select, custom_currency
            JOIN convert_currency_with_detail (
                                _amount:= promo_select.value, 
                                _from_currency_type_id:= promo_select.currency_type_id,
                                _to_currency_type_id:= tc_id_from_name('currency_type', custom_currency.value) ) p ON TRUE
        ), multiple_years AS (
            SELECT 
                CASE WHEN promo_select.period = 1 AND promo_select.is_promo_applied_to_1_year_registrations_only 
                    THEN promo_select_custom_currency.value + tier_price_custom_currency.value
                WHEN promo_select.period != 1 
                    THEN promo_select_custom_currency.value 
                    ELSE _period * promo_select_custom_currency.value 
                END value
            FROM promo_select, promo_select_custom_currency, tier_price_custom_currency
        ), json_build AS (
            SELECT
                jsonb_build_object(
                        'promo_price_value', 								promo_select.value, 
                        'promo_price_cur', 									promo_select_custom_currency.from_currency, 
                        'promo_price_exchange_rate', 						promo_select_custom_currency.from_exchange_rate,
                        'promo_price_currency_type_id', 					promo_select_custom_currency.from_currency_type_id,
                        'is_promo_applied_to_1_year_registrations_only', 	promo_select.is_promo_applied_to_1_year_registrations_only,
                        'is_rebate',                                        promo_select.is_rebate,
                        'customer_currency',  								promo_select_custom_currency.to_currency, 
                        'customer_exchange_rate', 							promo_select_custom_currency.to_exchange_rate, 
                        'multiple years value', 							multiple_years.value
                        ) AS ad
            FROM promo_select, promo_select_custom_currency, multiple_years, roundup
        )   SELECT 
                multiple_years.value::DECIMAL(19, 4) AS total_price,
                promo_select_custom_currency.to_currency AS currency,
                promo_select_custom_currency.to_exchange_rate::DECIMAL(19, 4) AS currency_exchange_rate, 
                promo_select.price_type, 
                promo_select.price_type_id,
                CASE WHEN promo_select.is_promo_applied_to_1_year_registrations_only THEN 
                    tier_price.price_detail || json_build.ad
                    ELSE json_build.ad
                END price_detail
            FROM multiple_years, roundup, promo_select_custom_currency, promo_select,  tier_price, json_build; 

    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION get_domain_price(
        _tenant_customer_id UUID,
        _accreditation_tld_id UUID, 
        _order_type_id UUID, 
        _period INTEGER DEFAULT 1,
        _period_type_id UUID DEFAULT tc_id_from_name('period_type','year'), 
        _reg_fee INTEGER DEFAULT NULL, 
        _reg_currency TEXT DEFAULT NULL, 
        _date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
    RETURNS SETOF price_data_type
    AS $$
    DECLARE
        price_detail RECORD; 
    BEGIN 
        SELECT *
            INTO price_detail
        FROM get_domain_price_premium (
            _accreditation_tld_id:= _accreditation_tld_id, 
            _tenant_customer_id:= _tenant_customer_id,
            _reg_fee:= _reg_fee, 
            _reg_currency:= _reg_currency);

        IF price_detail.total_price IS NOT NULL THEN 
            RETURN QUERY
                SELECT 
                    price_detail.total_price,
                    price_detail.currency,
                    price_detail.currency_exchange_rate,
                    price_detail.price_type,
                    price_detail.price_type_id,
                    price_detail.price_detail; 
            RETURN; 
        END IF; 

        SELECT *
            INTO price_detail
        FROM get_domain_price_promo (
            _accreditation_tld_id:= _accreditation_tld_id, 
            _order_type_id:= _order_type_id, 
            _tenant_customer_id:= _tenant_customer_id,
            _period:= _period,
            _period_type_id:= _period_type_id,
            _date:= _date);

        IF price_detail.total_price IS NOT NULL THEN  
            RETURN QUERY
                SELECT 
                    price_detail.total_price,
                    price_detail.currency,
                    price_detail.currency_exchange_rate,
                    price_detail.price_type,
                    price_detail.price_type_id,
                    price_detail.price_detail; 
            RETURN; 
        END IF; 

        SELECT *
            INTO price_detail
        FROM get_domain_price_custom(
            _accreditation_tld_id:= _accreditation_tld_id, 
            _order_type_id:= _order_type_id, 
            _tenant_customer_id:= _tenant_customer_id,
            _period:= _period,
            _period_type_id:= _period_type_id,
            _date:= _date);

        IF price_detail.total_price IS NOT NULL THEN 
            RETURN QUERY
                SELECT 
                    price_detail.total_price,
                    price_detail.currency,
                    price_detail.currency_exchange_rate,
                    price_detail.price_type,
                    price_detail.price_type_id,
                    price_detail.price_detail; 
            RETURN; 
        END IF; 

        SELECT *
            INTO price_detail
        FROM  get_domain_price_tier (
            _accreditation_tld_id:= _accreditation_tld_id, 
            _order_type_id:= _order_type_id, 
            _tenant_customer_id:= _tenant_customer_id,
            _period:= _period,
            _period_type_id:= _period_type_id,
            _date:= _date);

        IF price_detail.total_price IS NOT NULL THEN 
            RETURN QUERY
                SELECT 
                    price_detail.total_price,
                    price_detail.currency,
                    price_detail.currency_exchange_rate,
                    price_detail.price_type,
                    price_detail.price_type_id,
                    price_detail.price_detail; 
            RETURN; 
        END IF; 
    END;
    $$ LANGUAGE plpgsql;  

-- db/price/triggers.ddl 
     CREATE OR REPLACE TRIGGER tg_refresh_mv_product_customer_tier
        AFTER INSERT OR UPDATE OR DELETE ON product_customer_tier
        FOR EACH STATEMENT
        EXECUTE FUNCTION refresh_mv_product_customer_tier();

     CREATE OR REPLACE TRIGGER tg_refresh_mv_product_price_strategy
        AFTER INSERT OR UPDATE OR DELETE ON product_price_strategy
        FOR EACH STATEMENT
        EXECUTE FUNCTION refresh_mv_product_price_strategy();

     CREATE OR REPLACE TRIGGER tg_refresh_mv_domain_price_tier
        AFTER INSERT OR UPDATE OR DELETE ON domain_price_tier
        FOR EACH STATEMENT
        EXECUTE FUNCTION refresh_mv_domain_price_tier();

     CREATE OR REPLACE TRIGGER tg_refresh_mv_domain_premium_margin
        AFTER INSERT OR UPDATE OR DELETE ON domain_premium_margin 
        FOR EACH STATEMENT
        EXECUTE FUNCTION refresh_mv_domain_premium_margin();

     CREATE OR REPLACE TRIGGER tg_refresh_mv_domain_price_custom
        AFTER INSERT OR UPDATE OR DELETE ON domain_price_custom
        FOR EACH STATEMENT
        EXECUTE FUNCTION refresh_mv_domain_price_custom();

     CREATE OR REPLACE TRIGGER tg_refresh_mv_domain_price_tenant_promo
        AFTER INSERT OR UPDATE OR DELETE ON domain_price_tenant_promo
        FOR EACH STATEMENT
        EXECUTE FUNCTION refresh_mv_domain_price_tenant_promo();

     CREATE OR REPLACE TRIGGER tg_refresh_mv_domain_price_customer_promo
        AFTER INSERT OR UPDATE OR DELETE ON domain_price_customer_promo
        FOR EACH STATEMENT
        EXECUTE FUNCTION refresh_mv_domain_price_customer_promo();

-- db/price/init.sql 
    INSERT INTO promo_type
        ("name", descr)
        VALUES
            ('percent discount', 'A promotion that offers a percentage off the original price.'),
            ('fixed discount', 'A promotion that offers a fixed amount off the original price.'),
            ('fixed price', 'A promotion that offers a product at a fixed promotional price.')
        ON CONFLICT DO NOTHING; 

    INSERT INTO price_type
            ("name", descr, overrides)
            VALUES
                ('tier', 'The tier price for the named tier. This tier price is attributed to all customer accounts that have been assigned that tier', NULL),
                ('premium', 'The price assigned for a premium domain under the named TLD, calculated as a markup in % on top of the cost indicated in the EPP Fee Check', NULL),
                ('repeating charge', 'A price for a repeating charge, tied to a range of products, that should get billed to a reseller account even where that charge may not be tied to a particular product or cost', NULL)
            ON CONFLICT DO NOTHING; 

    INSERT INTO price_type
        ("name", descr, overrides)
        VALUES(     
            UNNEST(ARRAY[
                'custom', 
                'custom - cost+'
            ]),
            UNNEST(ARRAY[
                'A custom price, which overrides the assigned tier price for the given product and order type for whichever account(s) it is assigned to. Cannot be combined with Custom - Cost+',
                'A custom price, calculated by the system based on the markup amount indicated - the markup price is automatically added on top of the USD converted cost to determine the price. Cannot be combined with Custom'   
            ]),
            ARRAY[(SELECT id 
            FROM price_type
            WHERE name = 'tier')]
        ) ON CONFLICT DO NOTHING; 

    INSERT INTO price_type
        ("name", descr, overrides)
        VALUES
            ('promo - all', 
            'The promotional price assigned to a product and order type for a designated period of time - automatically assigned to all reseller accounts for that brand. Cannot be combined with Promo - Signup',
            ARRAY[(SELECT id 
                    FROM price_type
                    WHERE name = 'tier'),
                (SELECT id 
                    FROM price_type
                    WHERE name = 'custom')
            ]), 
            ('promo - signup', 
            'The promotional price assigned to designated reseller accounts (or account groups), for a designated period of time. Resellers have to sign up to receive this pricing. Cannot be combined with Promo - ALL',
            ARRAY[(SELECT id 
                    FROM price_type
                    WHERE name = 'tier'),
                (SELECT id 
                    FROM price_type
                    WHERE name = 'custom')
            ])ON CONFLICT DO NOTHING; 

    INSERT INTO price_type
        ("name", descr, overrides)
        VALUES        
            ( 'promo - custom',
            'The custom promotional price assigned to a designated reseller account (or group), for a designated period of time',
            ARRAY[(SELECT id 
                    FROM price_type
                    WHERE name = 'promo - all'),
                (SELECT id 
                    FROM price_type
                    WHERE name = 'promo - signup'),
                (SELECT id 
                    FROM price_type
                    WHERE name = 'tier'),
                (SELECT id 
                    FROM price_type
                    WHERE name = 'custom')])
        ON CONFLICT DO NOTHING; 

    INSERT INTO price_type
        ("name", descr, overrides)
        VALUES   
            ('custom - premium',
            'The custom price assigned to a reseller account for a premium domain under the named TLD, calculated as a markup in % on top of the cost indicated in the EPP Fee Check',
            ARRAY[(SELECT id 
            FROM price_type
            WHERE name = 'premium')])
        ON CONFLICT DO NOTHING; 

    UPDATE price_type
        SET level = CASE 
            WHEN name = 'tier' THEN 1
            WHEN name = 'custom' THEN 2
            WHEN name = 'custom - cost+' THEN 2
            WHEN name = 'promo - all' THEN 3
            WHEN name = 'promo - signup' THEN 3
            WHEN name = 'promo - custom' THEN 4
            WHEN name = 'premium' THEN 10
            WHEN name = 'custom - premium' THEN 11
            WHEN name = 'repeating charge' THEN 100
            ELSE 0  
        END;

    INSERT INTO product_cost_range
        (product_id, value)
        VALUES
            (tc_id_from_name('product','domain'), numrange(0, 10000, '[)')), 
            (tc_id_from_name('product','domain'), numrange(10000, 50000, '[)')), 
            (tc_id_from_name('product','domain'), numrange(50000, 150000, '[)')), 
            (tc_id_from_name('product','domain'), numrange(150000, NULL, '[)'))
        ON CONFLICT DO NOTHING;  

-- db/price/views.ddl
    DROP MATERIALIZED VIEW IF EXISTS mv_product_customer_tier; 
    CREATE MATERIALIZED VIEW mv_product_customer_tier AS
        WITH latest_product_customer_tier AS (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY tenant_customer_id, product_tier_type_id ORDER BY start_date DESC) AS rn
            FROM product_customer_tier pct
        )
        SELECT 
            t.name AS tenant_name, 
            cu.name AS customer_name,
            tt.name AS product_tier_type_name,
            pct.id AS product_customer_tier_id,
            pct.tenant_customer_id,
            pct.product_tier_type_id,
            pct.start_date AS product_customer_tier_start_date,
            tc.tenant_id, 
            tc.customer_id, 
            tc.customer_number, 
            t.business_entity_id AS tenant_business_entity_id, 
            cu.business_entity_id AS customer_business_entity_id
        FROM latest_product_customer_tier pct
        JOIN tenant_customer tc ON tc.id = pct.tenant_customer_id
        JOIN tenant t ON t.id = tc.tenant_id 
        JOIN customer cu ON cu.id = tc.customer_id 
        JOIN product_tier_type tt ON tt.id = pct.product_tier_type_id
        WHERE pct.start_date <= NOW() 
            AND pct.rn = 1;

    CREATE UNIQUE INDEX idx_mv_product_customer_tier ON mv_product_customer_tier (product_customer_tier_id);

    DROP MATERIALIZED VIEW IF EXISTS mv_product_price_strategy;
    CREATE MATERIALIZED VIEW mv_product_price_strategy AS
        SELECT 
            pt."name", 
            pps.level,
            pps.iteration_order,
            pps.id AS product_price_strategy_id,
            pps.product_id,
            pps.price_type_id,
            pt.descr,
            pt.overrides
        FROM product_price_strategy pps 
        JOIN price_type pt ON pt.id = pps.price_type_id;

    CREATE UNIQUE INDEX idx_mv_product_price_strategy ON mv_product_price_strategy (product_price_strategy_id);

    DROP MATERIALIZED VIEW IF EXISTS mv_domain_price_tier;
    CREATE MATERIALIZED VIEW mv_domain_price_tier AS
        WITH latest_domain_price_tier AS (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY tenant_id, order_type_id, accreditation_tld_id, period, product_tier_type_id 
                ORDER BY validity DESC) AS rn
            FROM domain_price_tier
        )	
        SELECT 
            pt."name" AS price_type,
            t."name" AS tenant,
            tld.name AS tld,
            vot.product_name,
            vot."name" AS order_type,
            ptt."name" AS product_tier_type,
            dpt.value,
            ct.name AS currency,
            dpt.period,
            pt2.name AS period_type,
            dpt.id AS domain_price_tier_id,
            dpt.tenant_id,
            dpt.price_type_id,
            dpt.order_type_id,
            dpt.product_tier_type_id,
            dpt.period_type_id,
            dpt.currency_type_id,
            dpt.validity,
            dpt.accreditation_tld_id
        FROM latest_domain_price_tier dpt 
        JOIN tenant t ON t.id = dpt.tenant_id
        JOIN price_type pt ON pt.id = dpt.price_type_id
        JOIN v_order_type vot ON vot.id = dpt.order_type_id
        JOIN accreditation_tld at2 ON at2.id = dpt.accreditation_tld_id
        JOIN provider_instance_tld pit ON pit.id = at2.provider_instance_tld_id 
        JOIN tld ON tld.id = pit.tld_id
        JOIN product_tier_type ptt ON ptt.id = dpt.product_tier_type_id
            AND ptt.product_id = tc_id_from_name('product','domain') 
        JOIN currency_type ct ON ct.id = dpt.currency_type_id
        JOIN period_type pt2 ON pt2.id = dpt.period_type_id
        WHERE dpt.rn = 1
        ORDER BY t."name", tld.name, vot.product_name, vot."name", ptt."name";

    CREATE UNIQUE INDEX idx_mv_domain_price_tier ON mv_domain_price_tier (domain_price_tier_id);

    DROP MATERIALIZED VIEW IF EXISTS mv_domain_premium_margin;
    CREATE MATERIALIZED VIEW mv_domain_premium_margin AS
        WITH latest_domain_premium_margin AS (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY price_type_id, product_cost_range_id, tenant_customer_id, accreditation_tld_id
                ORDER BY start_date DESC) AS rn
            FROM domain_premium_margin  
        )
        SELECT 
            pt."name" AS price_type,
            tld.name AS tld,
            pcr.value AS cost_range,
            vtc.tenant_name,
            vtc."name" AS customer_name,
            dpm.value,
            dpm.start_date,
            dpm.id,
            dpm.price_type_id,
            dpm.product_cost_range_id,
            dpm.tenant_customer_id,
            dpm.accreditation_tld_id
        FROM latest_domain_premium_margin dpm 
        JOIN price_type pt ON pt.id = dpm.price_type_id
        LEFT JOIN v_tenant_customer vtc ON vtc.id = dpm.tenant_customer_id
        LEFT JOIN accreditation_tld at2 ON at2.id = dpm.accreditation_tld_id
        LEFT JOIN provider_instance_tld pit ON pit.id = at2.provider_instance_tld_id 
        LEFT JOIN tld ON tld.id = pit.tld_id
        JOIN product_cost_range pcr ON pcr.id = dpm.product_cost_range_id 
            AND pcr.product_id = tc_id_from_name('product','domain')
        WHERE dpm.rn = 1;

    CREATE UNIQUE INDEX idx_mv_domain_premium_margin ON mv_domain_premium_margin (id);

    DROP MATERIALIZED VIEW IF EXISTS mv_domain_price_custom;
    CREATE MATERIALIZED VIEW mv_domain_price_custom AS
        WITH latest_domain_price_custom AS (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY tenant_customer_id, price_type_id, order_type_id, accreditation_tld_id, period ORDER BY validity DESC, id DESC) AS rn
            FROM domain_price_custom
        )
        SELECT 
            pt."name" AS price_type,
            tld.name AS tld,
            vot.product_name,
            vot."name" AS order_type,
            dpc.value,
            ct.name AS currency,
            dpc.period,
            pt2.name AS period_type,
            dpc.is_promo_cost_supported,
            dpc.validity,
            vtc.tenant_name,
            vtc."name" AS customer_name,
            dpc.id,
            dpc.tenant_customer_id,
            dpc.price_type_id,
            dpc.order_type_id,
            dpc.accreditation_tld_id,
            dpc.period_type_id,
            dpc.currency_type_id	
        FROM latest_domain_price_custom dpc
        JOIN v_tenant_customer vtc ON vtc.id = dpc.tenant_customer_id
        JOIN price_type pt ON pt.id = dpc.price_type_id
        JOIN v_order_type vot ON vot.id = dpc.order_type_id
        JOIN accreditation_tld at2 ON at2.id = dpc.accreditation_tld_id
        JOIN provider_instance_tld pit ON pit.id = at2.provider_instance_tld_id 
        JOIN tld ON tld.id = pit.tld_id
        JOIN currency_type ct ON ct.id = dpc.currency_type_id
        JOIN period_type pt2 ON pt2.id = dpc.period_type_id
        WHERE dpc.rn = 1;

    CREATE UNIQUE INDEX idx_mv_domain_price_custom ON mv_domain_price_custom (id);

    DROP MATERIALIZED VIEW IF EXISTS mv_domain_price_tenant_promo;
    CREATE MATERIALIZED VIEW mv_domain_price_tenant_promo AS
        WITH latest_domain_price_tenant_promo AS (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY tenant_id, price_type_id, promo_type_id, order_type_id, accreditation_tld_id, period ORDER BY validity DESC, id DESC) AS rn
            FROM domain_price_tenant_promo
        )
        SELECT 
            t."name" AS tenant,
            pt."name" AS price_type,
            prt.name AS promo_type,
            vot.product_name,
            vot."name" AS order_type,
            tld.name AS tld,
            dptp.value,
            ct.name AS currency,
            dptp.period,
            pt2.name AS period_type,
            dptp.is_promo_applied_to_1_year_registrations_only,
            dptp.is_rebate,
            dptp.validity,
            dptp.id,
            dptp.tenant_id,
            dptp.price_type_id,
            dptp.order_type_id,
            dptp.promo_type_id,
            dptp.accreditation_tld_id,
            dptp.period_type_id,
            dptp.currency_type_id
        FROM latest_domain_price_tenant_promo dptp
        JOIN price_type pt ON pt.id = dptp.price_type_id
        JOIN promo_type prt ON prt.id = dptp.promo_type_id
        JOIN tenant t ON t.id = dptp.tenant_id
        JOIN v_order_type vot ON vot.id = dptp.order_type_id
        JOIN accreditation_tld at2 ON at2.id = dptp.accreditation_tld_id
        JOIN provider_instance_tld pit ON pit.id = at2.provider_instance_tld_id 
        JOIN tld ON tld.id = pit.tld_id
        JOIN period_type pt2 ON pt2.id = dptp.period_type_id
        JOIN currency_type ct ON ct.id = dptp.currency_type_id
        WHERE dptp.rn = 1;

    CREATE UNIQUE INDEX idx_mv_domain_price_tenant_promo ON mv_domain_price_tenant_promo (id);

    DROP MATERIALIZED VIEW IF EXISTS mv_domain_price_customer_promo;
    CREATE MATERIALIZED VIEW mv_domain_price_customer_promo AS
        WITH latest_domain_price_customer_promo AS (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY tenant_customer_id, price_type_id, promo_type_id, order_type_id, accreditation_tld_id, period ORDER BY validity DESC, id DESC) AS rn
            FROM domain_price_customer_promo
        )
        SELECT 
            pt."name" AS price_type,
            vtc.name AS customer,
            prt.name AS promo_type,
            vot.product_name,
            vot."name" AS order_type,
            tld.name AS tld,
            dpcp.value,
            ct.name AS currency,
            dpcp.period,
            pt2.name AS period_type,
            dpcp.is_promo_applied_to_1_year_registrations_only,
            dpcp.is_rebate, 
            dpcp.validity,
            dpcp.id,
            dpcp.tenant_customer_id,
            dpcp.price_type_id,
            dpcp.promo_type_id,
            dpcp.order_type_id,
            dpcp.accreditation_tld_id,
            dpcp.period_type_id,
            dpcp.currency_type_id
        FROM latest_domain_price_customer_promo dpcp 
        JOIN v_tenant_customer vtc ON vtc.id = dpcp.tenant_customer_id
        JOIN price_type pt ON pt.id = dpcp.price_type_id
        JOIN promo_type prt ON prt.id = dpcp.promo_type_id
        JOIN v_order_type vot ON vot.id = dpcp.order_type_id
        JOIN accreditation_tld at2 ON at2.id = dpcp.accreditation_tld_id
        JOIN provider_instance_tld pit ON pit.id = at2.provider_instance_tld_id 
        JOIN tld ON tld.id = pit.tld_id
        JOIN period_type pt2 ON pt2.id = dpcp.period_type_id
        JOIN currency_type ct ON ct.id = dpcp.currency_type_id
        WHERE dpcp.rn = 1;

    CREATE UNIQUE INDEX idx_mv_domain_price_customer_promo ON mv_domain_price_customer_promo (id);

--- continue with the rest of the file

    INSERT INTO domain_premium_margin 
        (product_cost_range_id, price_type_id, value, start_date)
        VALUES(   
            UNNEST(ARRAY [(SELECT id FROM product_cost_range cr WHERE value @> numrange(1, 10000, '[)')) ,
                (SELECT id FROM product_cost_range cr WHERE value @> numrange(10000, 50000, '[)')),
                (SELECT id FROM product_cost_range cr WHERE value @> numrange(50000, 150000, '[)')), 
                (SELECT id FROM product_cost_range cr WHERE value @> numrange(150000, null, '[)'))]),
            tc_id_from_name('price_type','premium'),
            unnest(array[ 35,30,25,20]), 
            TIMESTAMPTZ '2024-01-01 00:00:00 UTC')
        ON CONFLICT DO NOTHING; 

    INSERT INTO product_tier_type
        (product_id, "name")
        SELECT
            tc_id_from_name('product','domain'),
            UNNEST(ARRAY[
                'essential', 
                'advanced',
                'premium',
                'enterprise'
            ])ON CONFLICT DO NOTHING; 

    INSERT INTO repeating_charge_type
        (name, descr)
        VALUES 
        ('monthly minimum amount', 'billed monthly minimum amount or transactional amount if it is larger then monthly minimum amount' )
    ON CONFLICT DO NOTHING; 

    INSERT INTO product_price_strategy
        (product_id, price_type_id, level, iteration_order)
        SELECT
            tc_id_from_name('product','domain'),
            id,
            level, 
            CASE 
                WHEN name = 'tier' THEN 1
                WHEN name = 'custom' OR name = 'custom - cost+' THEN 3
                WHEN name = 'promo - all' THEN 5
                WHEN name = 'promo - signup' OR name = 'promo - custom' THEN 7
                WHEN name = 'premium' OR name = 'custom - premium' THEN 10
                WHEN name = 'repeating charge' THEN 100
                ELSE 0
            END iteration_order
        FROM price_type
    ON CONFLICT DO NOTHING; 