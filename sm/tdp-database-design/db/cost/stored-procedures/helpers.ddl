--
-- function: refresh_mv_XXX 
-- description: mv has index, and refresh_mv_xxx allows concurrently refresh mv 
--

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

-- function: get_order_type_id( _order_type TEXT, _product TEXT) 
-- description: This function returns an UUID representing a row ID 
--              from a table order_type
--              it takes a number of parameters given in parentheses

CREATE OR REPLACE FUNCTION get_order_type_id( _order_type TEXT, _product TEXT) 
RETURNS UUID AS $$
DECLARE
  _result UUID;
BEGIN
	SELECT vot.id 
		INTO _result
	FROM v_order_type vot
		WHERE vot."name" = _order_type
			AND vot.product_name = _product  ; 
  RETURN _result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- function: get_tenant_customer_id ( _tenant TEXT, _customer TEXT) 
-- description: This function returns an UUID representing a row ID 
--              from a table tenant_customer
--              it takes a number of parameters given in parentheses

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

-- function: get_accreditation_tld_id( _tenant TEXT, _tld TEXT) 
-- description: This function returns an UUID representing a row ID 
--              from a table accreditation_tld
--              it takes a number of parameters given in parentheses

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

--
-- function: get_nonpromo_cost(_accreditation_tld_id UUID, _order_type_id UUID)
-- description: function returns cost for 1 year without promotion 
--

CREATE OR REPLACE FUNCTION get_nonpromo_cost(_accreditation_tld_id UUID, 
                                                _order_type_id UUID, 
                                                _period INTEGER DEFAULT 1, 
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

-- function: get_provider_instance_tld_id(_accreditation_tld_id UUID)
-- description: 
-- 

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
