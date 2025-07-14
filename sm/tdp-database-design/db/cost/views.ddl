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
    pt.name AS period_type, 
    dcc.period_type_id, 
    dcc.currency_type_id,
    dcc.accreditation_tld_id
  FROM latest_cost_domain_component dcc
  JOIN cost_component_type cct ON cct.id = dcc.cost_component_type_id
  JOIN accreditation_tld act ON act.id = dcc.accreditation_tld_id
  JOIN provider_instance_tld pit ON pit.id = act.provider_instance_tld_id
  JOIN tld ON tld.id = pit.tld_id
  LEFT JOIN order_type ot ON ot.id = dcc.order_type_id
  LEFT JOIN currency_type ct ON ct.id = dcc.currency_type_id
  LEFT JOIN period_type pt ON pt.id = dcc.period_type_id
  WHERE dcc.rn = 1
  ORDER BY tld.name, 
    CASE
      WHEN is_promo IS TRUE THEN 1
      ELSE 2
    END;

CREATE UNIQUE INDEX idx_mv_cost_domain_component ON mv_cost_domain_component (id);

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
