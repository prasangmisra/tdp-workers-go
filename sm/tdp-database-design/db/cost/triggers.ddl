-- Triggers for Concurrent Refresh for Materialized View 
CREATE TRIGGER refresh_mv_cost_domain_component_tg
	AFTER INSERT ON cost_domain_component
	FOR EACH ROW
	EXECUTE FUNCTION refresh_mv_cost_domain_component();

CREATE TRIGGER refresh_mv_currency_exchange_rate_tg 
	AFTER INSERT ON currency_exchange_rate
	FOR EACH ROW
	EXECUTE FUNCTION refresh_mv_currency_exchange_rate(); 

CREATE TRIGGER refresh_mv_order_type_period_type_tg
	AFTER INSERT ON order_type_period_type
	FOR EACH ROW
	EXECUTE FUNCTION refresh_mv_order_type_period_type(); 

-- there should be a manual process from UI that triggers generation of fees into component table; 
-- TODO: update/auto generate components when the values had been updated like ICANN_fee 



/*
-- 1. Execute autopopulate_cost_domain_component_icannfee first
CREATE TRIGGER a_autopopulate_cost_domain_component_icannfee_tg 
	AFTER INSERT ON accreditation_tld
	FOR EACH ROW
	EXECUTE FUNCTION autopopulate_cost_domain_component_icannfee();

-- 2. Execute autopopulate_sku_accreditation_tld_tg second
CREATE TRIGGER b_autopopulate_sku_accreditation_tld_tg
	AFTER UPDATE ON accreditation_tld
	FOR EACH ROW
	EXECUTE FUNCTION autopopulate_sku();

-- 3. Execute autopopulate_cost_domain_component_bankfee_tg second
CREATE TRIGGER a_autopopulate_cost_domain_component_bankfee_tg 
	AFTER INSERT ON cost_domain_component
	FOR EACH ROW
	EXECUTE FUNCTION autopopulate_cost_domain_component_bankfee();

-- 4. Execute autopopulate_cost_domain_component_taxfee_tg third
CREATE TRIGGER b_autopopulate_cost_domain_component_taxfee_tg 
	AFTER INSERT ON cost_domain_component
	FOR EACH ROW
	EXECUTE FUNCTION autopopulate_cost_domain_component_taxfee();

TODO: Wait till we have a workflow for intercompany purchase  
-- 5. Execute autopopulate_cost_domain_component_interfee_tg sixth 
CREATE TRIGGER c_autopopulate_cost_domain_component_interfee_tg 
	AFTER INSERT ON cost_domain_component
	FOR EACH ROW
	EXECUTE FUNCTION autopopulate_cost_domain_component_interfee();


-- 6. Execute autopopulate_sku_order_type_tg first 
CREATE TRIGGER auto_populate_sku_order_type_tg
	AFTER UPDATE ON order_type_period_type
	FOR EACH ROW
	EXECUTE FUNCTION autopopulate_sku();
*/ 











