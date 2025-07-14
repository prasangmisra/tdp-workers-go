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
