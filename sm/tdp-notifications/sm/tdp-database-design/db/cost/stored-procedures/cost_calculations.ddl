--
-- function: insert_rec_cost_domain_component(parameters)
-- description: Inserts calculated components into the cost_domain_component table if they have not been inserted before.
--              This function checks if the calculated cost components are already present in the cost_domain_component table.
--              If they are not present, it proceeds to insert them.

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

--
-- functions: seed_XXXFEE_cost_domain_component()
-- description: Evaluates components icann_fee/tax_fee/inter_fee/bank_fee and passes value to insert into cost_domain_component table
--              returns nothing
-- function needs to insert value if tld is 'generic' & does not have parent_tld_id else 0;  

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

--
-- functions: seed_XXXFEE_cost_domain_component()
-- description: Evaluates components icann_fee/tax_fee/inter_fee/bank_fee and passes value to insert into cost_domain_component table
--              returns nothing
-- function needs to insert value if currency registry != tenant.accepts_currencies

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

--
-- functions: seed_XXXFEE_cost_domain_component()
-- description: Evaluates components icann_fee/tax_fee/inter_fee/bank_fee and passes value to insert into cost_domain_component table
--              returns nothing
-- function needs to  insert value if it is given finance_settings otherwise returns nothing 

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

-- TODO: wait till we have a flow to build intercompany fee 
/*
    CREATE OR REPLACE FUNCTION cost_domain_component_interfee_onboarding()
    RETURNS VOID
    AS $$
    DECLARE
        rec_check RECORD; 
    BEGIN 
        RAISE NOTICE 'working inter fee trigger NEW.id %', NEW.id;
        -- inter fee 
        IF NEW.cost_component_type_id = tc_id_from_name('cost_component_type', 'registry fee') THEN 
            SELECT get_tld_setting(
                        p_key => 'tenant.finance_tenant.intercompany_pricing_fee',
                        p_accreditation_tld_id => NEW.accreditation_tld_id) AS value 
                ,FALSE AS is_promo 
                INTO rec_check 
            FROM cost_domain_component dcc
            JOIN accreditation_tld act ON act.id = dcc.accreditation_tld_id 
            JOIN accreditation a ON a.id =act.accreditation_id 
            JOIN provider_instance_tld pit ON pit.id = act.provider_instance_tld_id 
            JOIN tld_brand_fallback tbf ON tc_id_from_name('tld', tbf.tld_name) = pit.tld_id
            WHERE dcc.id = NEW.id;  
            RAISE NOTICE 'FOUND RECORD 4 rec_check %', rec_check; 

            IF FOUND THEN 
                PERFORM insert_rec_cost_domain_component(tc_id_from_name('cost_component_type','intercompany pricing fee'),
                                                NEW.accreditation_tld_id::UUID, 
                                                NULL::UUID, -- order_type_id 
                                                1::INTEGER, 
                                                rec_check.value::DECIMAL(19, 4),  
                                                NULL:: UUID, -- currency_type_id
                                                tstzrange(NOW() AT TIME ZONE 'UTC', 'infinity'),
                                                rec_check.is_promo);
            END IF;  
        END IF; 
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;    
*/ 

--
-- function: autopopulate_sku
-- description: generate a new sku every time new order has been added to the list of products
-- product, order_type, accreditation_tld, product_type_period_type 

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

--
-- function: get_total_cost_domain_components (parameters)
-- description: Function that returns individual components  
--              it updates/inserts total_cost into domain_cost table 
-- WHEN premium dont return registry fee = it will be recorded by separate function; 

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


-- COMMENT ON column promo_reg_fee and nonpromo_reg_fee IS Columns are returned as non NULL when cost_component is registry_fee and is_promo IS TRUE, 
-- and is_promo_applied_to_1_year_only IS TRUE - promo_cost is calculated with the loss of components =  promo_reg_fee + (_period - 1 ) * nonpromo_reg_fee


--
-- function: get_total_cost_domain (parameters)
-- description: Function returns total_cost 
--              it updates/inserts total_cost into domain_cost table  

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
         -- Calculate the total cost based on the cost component type and currency type
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


