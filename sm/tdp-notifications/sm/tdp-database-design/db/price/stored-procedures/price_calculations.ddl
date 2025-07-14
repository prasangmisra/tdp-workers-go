-- 
-- function: roundup(_amount, _roundup_to )  
-- description: This function returns rounded INTEGER 
--
CREATE OR REPLACE FUNCTION roundup(_amount DECIMAL(19, 5), _roundup_to INTEGER)  
RETURNS INTEGER
AS $$
BEGIN
    RETURN (CEIL(_amount / _roundup_to) * _roundup_to)::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- 
-- function: convert_currency_with_detail (_amount, _from_currency_type_id, _to_currency_type_id)
-- description: This function takes price_amount and converts it into USD, and then converts it into customer_currency OR final_currency_type_id 
--
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

-- 
-- function: signup_for_promotion()  
-- description: This function returns nothing; 
--              It allows to sign up for signup_promotion with tenant_customer_id & promotion info domain_price_customer_promo table
-- found value needs to be CONVERTED twice: from input currency 1. TO USD AND 2. TO client_currency 
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

-- 
-- function: show_domain_price_tier(parameters)
-- description: This function returns all_tier_prices( when 1st parameter is NULL) in input currency (NOT IN CUSTOMER CURRENCY)
-- or tier_price when it is given
-- 1.find all_tier_prices:                          show_domain_price_tier (NULL, _tenant_id, _accreditation_tld_id, _order_type_id)
-- 2.find the tier_price for _tenant_customer_id:   show_domain_price_tier (_tenant_customer_id, NULL, _accreditation_tld_id, _order_type_id)

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

-- Create the composite type for get_domain_price_XXX functions 
CREATE TYPE price_data_type AS (
    total_price DECIMAL(19, 4), -- INTEGER,
    currency TEXT,
    currency_exchange_rate DECIMAL(19, 4),
    price_type TEXT,
    price_type_id UUID,
    price_detail JSONB
);

-- function: get_domain_price_tier(parameters)
-- description: returns tier price for tenant_customer 
-- 
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

-- function: get_domain_price_custom(_tenant_customer_id UUID, _accreditation_tld_id UUID)
-- description: returns custom price if exists 
-- 
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

-- function: get_domain_price_premium (_tenant_customer_id UUID, _accreditation_tld_id UUID, reg_fee INTEGER, reg_cur TEXT)
-- description: returns price of premium domain with details
-- 

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

-- 
-- function: get_domain_price_promo(...) 
-- description: This function returns value of total_price for promo considering number of years and type of promotion (linear/non-linear/applicable to 1st year only/to all years)
--

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
                    --'general.round_up_non_premium',						roundup.value
                    ) AS ad
        FROM promo_select, promo_select_custom_currency, multiple_years, roundup
    )   SELECT 
            -- roundup( multiple_years.value, roundup.value)::DECIMAL(19, 4) AS total_price,
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

-- 
-- function: get_domain_price(...) 
-- description: returns price components for desired product  
-- comment: product_price_strategy.level < 100 finds everything except repeating charges that are not per product

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
    -- 1. premium

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

    -- 2. promo 
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

    -- 3. custom 

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

    -- 4. tier 
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