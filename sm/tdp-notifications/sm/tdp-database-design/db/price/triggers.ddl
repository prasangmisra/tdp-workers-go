-- Trigger for refresh_mv_product_customer_tier
CREATE TRIGGER tg_refresh_mv_product_customer_tier
	AFTER INSERT OR UPDATE OR DELETE ON product_customer_tier
	FOR EACH STATEMENT
	EXECUTE FUNCTION refresh_mv_product_customer_tier();

-- Trigger for refresh_mv_product_price_strategy
CREATE TRIGGER tg_refresh_mv_product_price_strategy
	AFTER INSERT OR UPDATE OR DELETE ON product_price_strategy
	FOR EACH STATEMENT
	EXECUTE FUNCTION refresh_mv_product_price_strategy();

-- Trigger for refresh_mv_domain_price_tier
CREATE TRIGGER tg_refresh_mv_domain_price_tier
	AFTER INSERT OR UPDATE OR DELETE ON domain_price_tier
	FOR EACH STATEMENT
	EXECUTE FUNCTION refresh_mv_domain_price_tier();

-- Trigger for refresh_mv_domain_premium_margin 
CREATE TRIGGER tg_refresh_mv_domain_premium_margin
	AFTER INSERT OR UPDATE OR DELETE ON domain_premium_margin 
	FOR EACH STATEMENT
	EXECUTE FUNCTION refresh_mv_domain_premium_margin();

-- Trigger for refresh_mv_domain_price_custom
CREATE TRIGGER tg_refresh_mv_domain_price_custom
	AFTER INSERT OR UPDATE OR DELETE ON domain_price_custom
	FOR EACH STATEMENT
	EXECUTE FUNCTION refresh_mv_domain_price_custom();

-- Trigger for refresh_mv_domain_price_tenant_promo
CREATE TRIGGER tg_refresh_mv_domain_price_tenant_promo
	AFTER INSERT OR UPDATE OR DELETE ON domain_price_tenant_promo
	FOR EACH STATEMENT
	EXECUTE FUNCTION refresh_mv_domain_price_tenant_promo();

-- Trigger for refresh_mv_domain_price_customer_promo
CREATE TRIGGER tg_refresh_mv_domain_price_customer_promo
	AFTER INSERT OR UPDATE OR DELETE ON domain_price_customer_promo
	FOR EACH STATEMENT
	EXECUTE FUNCTION refresh_mv_domain_price_customer_promo();




-- 1. with addition accreditation_tld add premium margin to  domain_price table 
/*CREATE TRIGGER t01_auto_populate_domain_price_premium_tg
	AFTER UPDATE ON accreditation_tld 
	FOR EACH ROW
	EXECUTE FUNCTION auto_populate_domain_price_premium(); 

-- 2. with addition tenant_cusotmer add premium margin to domain_price table 
CREATE TRIGGER t01_autopopulate_domain_price_premium_tg
	AFTER UPDATE ON tenant_customer 
	FOR EACH ROW
	EXECUTE FUNCTION autopopulate_domain_price_premium(); */




-- 7. TODO. add trigger & function to update cost & price with currency update 
/*
CREATE TRIGGER t01_exchange_rate_update_tg
	AFTER UPDATE ON currency_exchange_rate
	FOR EACH ROW
	EXECUTE FUNCTION exchange_rate_update(); */


/*
CREATE TRIGGER validity_update_before_insert_domain_cost_tg
	BEFORE INSERT ON domain_cost
	FOR EACH ROW
	EXECUTE FUNCTION validity_update();

CREATE TRIGGER validity_update_before_insert_product_cost_tg
	BEFORE INSERT ON product_cost
	FOR EACH ROW
	EXECUTE FUNCTION validity_update();

CREATE TRIGGER validity_update_before_insert_cost_domain_component_tg
	BEFORE INSERT ON cost_domain_component
	FOR EACH ROW
	EXECUTE FUNCTION validity_update();

CREATE TRIGGER validity_update_before_insert_exchange_rate_tg
	BEFORE INSERT ON currency_exchange_rate
	FOR EACH ROW
	EXECUTE FUNCTION validity_update();

CREATE TRIGGER validity_update_before_insert_product_customer_tier_tg
	BEFORE INSERT ON product_customer_tier
	FOR EACH ROW
	EXECUTE FUNCTION validity_update();

CREATE TRIGGER validity_update_before_insert_domain_price_tg
	BEFORE INSERT ON domain_price
	FOR EACH ROW
	EXECUTE FUNCTION validity_update();

CREATE TRIGGER validity_update_before_insert_product_price_tg
	BEFORE INSERT ON product_price
	FOR EACH ROW
	EXECUTE FUNCTION validity_update();

CREATE TRIGGER validity_update_before_insert_price_lookup_value_tg
	BEFORE INSERT ON price_lookup_value
	FOR EACH ROW
	EXECUTE FUNCTION validity_update();

CREATE TRIGGER exchange_rate_update_tg
	AFTER INSERT ON currency_exchange_rate
	FOR EACH ROW
	EXECUTE FUNCTION exchange_rate_update();
	
CREATE TRIGGER auto_populate_domain_price_table_tg
	AFTER INSERT ON price_lookup_value
	FOR EACH ROW
	EXECUTE FUNCTION auto_populate_domain_price_table();

CREATE TRIGGER auto_populate_account_tg
	AFTER INSERT ON tenant_customer
	FOR EACH ROW
	EXECUTE FUNCTION auto_populate_account();

CREATE TRIGGER auto_populate_lookup_price_table_tg
	AFTER INSERT ON accreditation_tld
	FOR EACH ROW
	EXECUTE FUNCTION auto_populate_lookup_price_table();

*/