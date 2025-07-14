
--1. RegOps Cost Data import;

CREATE TABLE "temp_enom_regops_cost" (
    "Parent TLD"            				TEXT
    ,"TLD"                  				TEXT	
    ,"TLD Type"           					TEXT	
    ,"Registry Name/ business_entity"     	TEXT	
    ,"Technical Backend/ provider"        	TEXT	
    ,"Order Type"    						TEXT	
    ,"Supported Period"            			TEXT	
    ,"Registry cost"     					TEXT	
    ,"Registry Cost Currency"      			TEXT	
    ,"ICANN fee"     						TEXT	
    ,"Tax/VAT/GST if applied"            	TEXT	
    ,"Manual Proc. Fee € (EURO)"            TEXT	
    ,"5% Intercompany fee"              	TEXT 	
    ,"Direct accreditation"          	 	TEXT
	,"Orders via (if required)"           	TEXT
	,"Updated by"           				TEXT
	,"Cost effective from "           		TEXT
); 

\copy temp_enom_regops_cost FROM 'test_finance_data/1_enom_cost_all_RegOps.csv' DELIMITER ',' CSV HEADER;

ALTER TABLE temp_enom_RegOps_cost
    ADD COLUMN parent_tld TEXT, 
    ADD COLUMN tld TEXT, 
    ADD COLUMN business_entity TEXT, 
    ADD COLUMN provider TEXT, 
    ADD COLUMN order_type TEXT,
    ADD COLUMN supported_period TEXT,
    ADD COLUMN registry_cost INTEGER,
    ADD COLUMN registry_currency TEXT,
    ADD COLUMN icann_fee BOOLEAN,
    ADD COLUMN tax_fee REAL,
    ADD COLUMN man_proc_fee REAL,
	ADD COLUMN intercompany_fee BOOLEAN,
   	ADD COLUMN direct_accreditation BOOLEAN,
    ADD COLUMN validity TSTZRANGE; 

UPDATE temp_enom_RegOps_cost
SET parent_tld = LOWER("Parent TLD"), 
	tld = LOWER("TLD"), 
	business_entity = LOWER("Registry Name/ business_entity"), 
	provider = LOWER("Technical Backend/ provider"), 
	order_type = CASE 
		WHEN "Order Type" = 'Register' THEN 'create'
		WHEN "Order Type" = 'Renew' THEN 'renew'
		WHEN "Order Type" = 'Transfer' THEN 'transfer_in'
		WHEN "Order Type" = 'Restore (RGP)' THEN 'redeem' -- per TRANSACTION 
		WHEN "Order Type" = 'Restore (extended RGP)' THEN 'redeem+' 
	END,
	supported_period = CASE 
		WHEN "Supported Period" = '0' THEN NULL 
		WHEN "Supported Period" = '1-10' THEN '1,2,3,4,5,6,7,8,9,10'
		WHEN "Supported Period" = '1-9' THEN '1,2,3,4,5,6,7,8,9'
		WHEN "Supported Period" = '1-5, 10' THEN '1,2,3,4,5,10'
		WHEN "Supported Period" = '1' THEN '1'
	END, 
	registry_cost = CASE 
		WHEN "Registry cost" = 'TBC' THEN NULL 
		ELSE CAST(CAST("Registry cost" AS NUMERIC) * 100 AS INTEGER)
		END, 
	registry_currency = "Registry Cost Currency",
	icann_fee = CASE 
		WHEN "ICANN fee"  = 'yes' THEN TRUE 
		ELSE FALSE 
	END,
	tax_fee = CAST(CAST("Tax/VAT/GST if applied" AS NUMERIC) * 100 AS REAL),
	man_proc_fee = CAST(CAST("Manual Proc. Fee € (EURO)" AS NUMERIC) * 100 AS INTEGER), 
	intercompany_fee = CASE 
		WHEN "5% Intercompany fee"  = 'yes' THEN TRUE 
		ELSE FALSE 
	END,
   	direct_accreditation = CASE 
		WHEN "Direct accreditation"  = 'yes' THEN TRUE 
		ELSE FALSE 
	END,
	validity = CASE
		WHEN "Cost effective from " IS NULL THEN tstzrange('2024-01-01 00:00:00'::timestamp with time zone, 'infinity', '[)')
		ELSE tstzrange("Cost effective from "::timestamp with time zone, 'infinity', '[)')
	END; 

/*
	INSERT INTO tld_brand_fallback 
		(brand_id, tld_name, default_tenant_id, validity)
	VALUES 
		(tc_id_from_name('tenant', 'enom'), 
		'au', 
		tc_id_from_name('tenant', 'opensrs'),
		tstzrange(('2024-01-01 00:00:00')::timestamp with time zone, 'infinity','[)')); 
*/

--2. TLD DATA 
	INSERT INTO business_entity(name,descr) --13 be-regs
		SELECT DISTINCT terc.business_entity, terc."Registry Name/ business_entity"
		FROM temp_enom_regops_cost terc; 
	
	INSERT INTO registry(business_entity_id,name,descr) -- 13
		SELECT DISTINCT 
			tc_id_from_name('business_entity',terc.business_entity),
			terc.business_entity || ' registry',
			terc."Registry Name/ business_entity" || ' Registry'
		FROM temp_enom_regops_cost terc;				
		
	INSERT INTO tld(name, registry_id, type_id) --221
		SELECT DISTINCT ON (terc.tld) terc.tld, 
			tc_id_from_name('registry', terc.business_entity || ' registry'), 
			CASE WHEN LENGTH(terc.tld) = 2 THEN tc_id_from_name('tld_type','country_code')
				ELSE tc_id_from_name('tld_type','generic') END
		FROM temp_enom_regops_cost terc
	WHERE terc.tld NOT IN (SELECT name FROM tld); 
			

	INSERT INTO business_entity(name,descr) 
		SELECT DISTINCT terc.provider, 
		terc."Technical Backend/ provider"
		FROM temp_enom_regops_cost terc
		WHERE terc.provider NOT IN (SELECT name FROM business_entity);

	INSERT INTO provider (business_entity_id,name,descr) 
		SELECT DISTINCT ON (terc.provider)
			tc_id_from_name('business_entity', terc.provider), 
			CASE WHEN terc.provider LIKE 'tucows%' THEN 'trs'
				WHEN terc.provider LIKE 'centralnic registry services' THEN 'centralnic-registry'
				ELSE REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', '') || ' registry services' END,
			REPLACE(REPLACE(terc."Technical Backend/ provider", ' Registry', ''), 'Services', '') || ' Registry Services'
		FROM temp_enom_regops_cost terc
		WHERE terc.provider NOT IN ('tucows registry services', 'centralnic');
		
	INSERT INTO provider_instance(provider_id,name,descr,is_proxy)
		SELECT DISTINCT ON (terc.provider) 
			tc_id_from_name('provider',REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', '') || ' registry services'),
			REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', '') || ' -default',
			REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', '') || ' instance', FALSE
		FROM temp_enom_regops_cost terc
		WHERE terc.provider NOT IN ('tucows registry services', 'centralnic');
	
	INSERT INTO provider_instance_tld(provider_instance_id,tld_id)  --221	
		SELECT DISTINCT ON (terc.tld)
			CASE WHEN terc.provider = 'tucows registry services' THEN tc_id_from_name('provider_instance', 'trs-uniregistry')
				WHEN terc.provider = 'centralnic' THEN tc_id_from_name('provider_instance', 'centralnic-default') 
				ELSE tc_id_from_name('provider_instance', REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', '') || ' -default') 
			END, 
			tc_id_from_name('tld', terc.tld)
		FROM temp_enom_regops_cost terc
		WHERE tc_id_from_name('tld', terc.tld) NOT IN (SELECT tld_id FROM provider_instance_tld); 

	INSERT INTO accreditation(tenant_id,provider_instance_id,name,registrar_id) 
		SELECT DISTINCT tc_id_from_name('tenant', 'enom'),
			tc_id_from_name('provider_instance', REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', '') || ' -default'), 
			'enom-' || REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', ''),
			'testdata'
		FROM temp_enom_regops_cost terc
		WHERE terc.provider NOT IN ('tucows registry services', 'centralnic');
				
	INSERT INTO accreditation_tld(accreditation_id,provider_instance_tld_id)
		SELECT DISTINCT 
			CASE WHEN terc.provider = 'tucows registry services' THEN tc_id_from_name('accreditation', 'enom-uniregistry')
				WHEN terc.provider = 'centralnic' THEN tc_id_from_name('accreditation', 'enom-centralnic')
				ELSE tc_id_from_name('accreditation', 'enom-' || REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', '')) END, 
			pit.id
		FROM temp_enom_regops_cost terc 
		JOIN provider_instance_tld pit 
			ON CASE WHEN terc.provider = 'tucows registry services' THEN pit.provider_instance_id = tc_id_from_name('provider_instance', 'trs-uniregistry')
				WHEN terc.provider = 'centralnic' THEN pit.provider_instance_id = tc_id_from_name('provider_instance', 'centralnic-default')
				ELSE pit.provider_instance_id = tc_id_from_name('provider_instance', REPLACE(REPLACE(terc.provider, ' registry', ''), 'services', '') || ' -default') END
			AND pit.tld_id = tc_id_from_name('tld', terc.tld)
		WHERE terc.tld NOT IN ('country','sexy','click','link','property');

--3. update registry currency @finance_setting
WITH sel AS (
	SELECT DISTINCT terc.tld,terc.registry_currency  
	FROM temp_enom_regops_cost terc 
	WHERE terc.registry_currency != 'USD'
)
INSERT INTO finance_setting (type_id, provider_instance_tld_id, value_text, validity)
SELECT 
    tc_id_from_name('finance_setting_type','provider_instance_tld.accepts_currency')
	, get_provider_instance_tld_id( get_accreditation_tld_id('enom'::TEXT, sel.tld))
	, sel.registry_currency
	, tstzrange('2024-01-01 UTC', 'infinity')
FROM sel ;

INSERT INTO finance_setting (type_id, provider_instance_tld_id, value_decimal, validity)
VALUES
    (tc_id_from_name('finance_setting_type','provider_instance_tld.tax_fee')
	, get_provider_instance_tld_id(get_accreditation_tld_id('enom'::TEXT, 'wtf'))
	, 17.8
	, tstzrange('2024-01-01 UTC', 'infinity'));

-- onboarding for TLDs 
DO $$
DECLARE
	i RECORD;
BEGIN
	FOR i IN (
		SELECT DISTINCT act.id AS accreditation_tld_id, 
						act.provider_instance_tld_id
		FROM accreditation_tld act 
		JOIN provider_instance_tld pit ON pit.id = act.provider_instance_tld_id 
		JOIN tld ON tld.id = pit.tld_id
		JOIN temp_enom_regops_cost t ON t.tld = tld.name
	)
	LOOP 
		PERFORM seed_icannfee_cost_domain_component(i.accreditation_tld_id); 
		PERFORM seed_bankfee_cost_domain_component(i.accreditation_tld_id, tc_id_from_name('tenant', 'enom'));
		PERFORM seed_taxfee_cost_domain_component(i.provider_instance_tld_id); 
	END LOOP;
END $$;


-- 0. COST DATA -----------------------------------------------------------

INSERT INTO cost_domain_component -- 0. REGISTRY COST
	(cost_component_type_id,
	order_type_id, 
	accreditation_tld_id,
	period,
	value,
	currency_type_id, 
	validity)
        SELECT
     	tc_id_from_name('cost_component_type','registry fee')
        ,get_order_type_id(terc.order_type, 'domain')
        ,get_accreditation_tld_id('enom', terc.tld)  -- ac.id 
        ,1
        ,terc.registry_cost
        ,ct.id 
        ,terc.validity
    FROM temp_enom_regops_cost terc
    JOIN currency_type ct ON ct.name = terc.registry_currency
    WHERE terc.order_type IN ('create', 'renew', 'transfer_in', 'redeem')
   		AND terc.registry_cost IS NOT NULL
   		AND terc.tld NOT IN ('country','sexy','click','link','property')
   		AND terc.registry_cost != 0 AND terc.registry_cost IS NOT NULL; 


-- PROMO (promo-all, pormo-custom, promo sign-up)
CREATE TABLE "temp_enom_promo" (
	"Status"			TEXT
	,"TLD"			TEXT
	,"Platforms"			TEXT
	,"Start Date (UTC)"			TEXT
	,"End Date (UTC)"			TEXT
	,"Audience"			TEXT
	,"Term"			TEXT
	,"Whoelsale_List_Cost_with_fees"			TEXT
	,"Wholesale_Promo_Cost_with_fees"			TEXT
	,"Wholesale_List_Price"			TEXT
	,"Wholesale_Promo_Price"			TEXT
	,"Annual MDF"			TEXT
	,"Registration Rebates"			TEXT
	,"Contract Link"			TEXT
	,"Notes"			TEXT
	,"To Do"			TEXT
	,"Asana Task"			TEXT
	,"Jira Ticket"			TEXT
	,"Promo ID"			TEXT
); 

\copy temp_enom_promo FROM 'test_finance_data/2_enom_promo_all.csv' DELIMITER ',' CSV HEADER;

ALTER TABLE "temp_enom_promo"
	ADD COLUMN is_ongoing BOOLEAN, 
	ADD COLUMN tld TEXT, 
	ADD COLUMN validity TSTZRANGE, 
	ADD COLUMN price_type TEXT,
	ADD COLUMN promo_type TEXT, 
	ADD COLUMN order_type TEXT,
	ADD COLUMN currency_name TEXT,
	ADD COLUMN original_cost INTEGER,
	ADD COLUMN promo_cost INTEGER,
	ADD COLUMN promo_regfee INTEGER,
	ADD COLUMN promo_price INTEGER;	

-- Add index to improve performance
CREATE INDEX idx_temp_enom_promo_tld ON temp_enom_promo (tld);

UPDATE "temp_enom_promo"
	SET 
		is_ongoing = CASE WHEN "Status" = 'LIVE' THEN TRUE
			WHEN "Status" = 'UPCOMING' THEN NULL 
			WHEN "Status" = 'DONE' THEN FALSE END,
		tld = LOWER(REPLACE("TLD", '.', '')), 
		validity = tstzrange(to_timestamp("Start Date (UTC)", 'YYYY Mon DD • HH:MI:SS AM UTC'), to_timestamp("End Date (UTC)", 'YYYY Mon DD • HH:MI:SS AM UTC'), '[)'),
		price_type = CASE WHEN "Audience" = 'Channel (sign up required)' OR "Audience" = 'Channel (signup required)' THEN	'promo - signup'
			WHEN "Audience" = 'Channel (no signup required)' THEN 'promo - all'	
			ELSE 'promo - custom' END,
		promo_type = 'fixed price', 
		order_type = CASE WHEN "Term" = 'New registrations, first year only' THEN 'create_1'
			WHEN "Term" = 'New registrations, renewals and transfers, all years' THEN 'create, renew, transfer_in'
			WHEN "Term" = 'Renewals, all years (multi-year)' THEN 'renew' END,	
		currency_name = CASE WHEN "Whoelsale_List_Cost_with_fees" LIKE '$%' THEN 'USD' 
			WHEN "Whoelsale_List_Cost_with_fees" LIKE '%EUR%' THEN 'EUR' END,
		original_cost = CASE WHEN  "Whoelsale_List_Cost_with_fees" LIKE '%EUR%' THEN 
			CAST(SUBSTRING("Whoelsale_List_Cost_with_fees", 1, POSITION('EUR' IN "Whoelsale_List_Cost_with_fees") - 1) AS NUMERIC) * 100
			ELSE CAST(CAST(REPLACE("Whoelsale_List_Cost_with_fees", '$', '') AS NUMERIC) * 100 AS INTEGER) END ,
		promo_cost = CASE WHEN  "Wholesale_Promo_Cost_with_fees" LIKE '%EUR%' THEN 
			CAST(SUBSTRING("Wholesale_Promo_Cost_with_fees", 1, POSITION('EUR' IN "Wholesale_Promo_Cost_with_fees") - 1) AS NUMERIC) * 100
			ELSE  CAST(CAST(REPLACE("Wholesale_Promo_Cost_with_fees", '$', '') AS NUMERIC) * 100 AS INTEGER) END, 
		promo_price = CASE WHEN "Wholesale_Promo_Price" = 'N/A' THEN 0
			ELSE CAST(CAST(REPLACE("Wholesale_Promo_Price", '$', '') AS NUMERIC) * 100 AS INTEGER) END;
UPDATE "temp_enom_promo"
	SET 			
		promo_regfee = promo_cost - 18
	WHERE tld NOT IN ('eu','me','io'); -- original_cost - promo_cost;
UPDATE "temp_enom_promo"
	SET 			
		promo_regfee = promo_cost
	WHERE tld IN ('eu','me', 'io'); 

-- Update order_type to 'transfer_in'
UPDATE temp_enom_promo
	SET order_type = 'transfer_in'
	WHERE order_type = 'create, renew, transfer_in';

UPDATE temp_enom_promo
	SET promo_price = 4800
	WHERE tld = 'io'; 

-- Insert records with order_type 'create' and 'renew' based on 'transfer_in' records
INSERT INTO temp_enom_promo
	SELECT 
		"Status"
		,"TLD"
		,"Platforms"
		,"Start Date (UTC)"
		,"End Date (UTC)"
		,"Audience"
		,"Term"
		,"Whoelsale_List_Cost_with_fees"
		,"Wholesale_Promo_Cost_with_fees"
		,"Wholesale_List_Price"
		,"Wholesale_Promo_Price"
		,"Annual MDF"
		,"Registration Rebates"
		,"Contract Link"
		,"Notes"
		,"To Do"
		,"Asana Task"
		,"Jira Ticket"
		,"Promo ID"
		,is_ongoing
		,tld
		,validity
		,price_type
		,promo_type
		,'create' AS order_type
		,currency_name
		,original_cost
		,promo_cost
		,promo_regfee
		,promo_price
	FROM temp_enom_promo
	WHERE order_type = 'transfer_in';

INSERT INTO temp_enom_promo
	SELECT
		"Status"
		,"TLD"
		,"Platforms"
		,"Start Date (UTC)"
		,"End Date (UTC)"
		,"Audience"
		,"Term"
		,"Whoelsale_List_Cost_with_fees"
		,"Wholesale_Promo_Cost_with_fees"
		,"Wholesale_List_Price"
		,"Wholesale_Promo_Price"
		,"Annual MDF"
		,"Registration Rebates"
		,"Contract Link"
		,"Notes"
		,"To Do"
		,"Asana Task"
		,"Jira Ticket"
		,"Promo ID"
		,is_ongoing
		,tld
		,validity
		,price_type
		,promo_type
		,'renew' AS order_type
		,currency_name
		,original_cost
		,promo_cost
		,promo_regfee
	FROM temp_enom_promo
	WHERE order_type = 'transfer_in';

UPDATE "temp_enom_promo"
	SET promo_type = 'fixed price',
		promo_regfee = promo_cost
	WHERE promo_regfee = 0;

-- customer/tld DATA

INSERT INTO tld(name,registry_id, type_id)
	SELECT DISTINCT  
		tep.tld, 
		tc_id_from_name('registry', 'identity digital limited registry'), 
		CASE WHEN LENGTH(tep.tld) = 2 THEN tc_id_from_name('tld_type','country_code')
			ELSE tc_id_from_name('tld_type','generic') END 
	FROM temp_enom_promo tep
	WHERE  tep.tld NOT IN (SELECT name FROM tld); 

INSERT INTO provider_instance_tld(provider_instance_id,tld_id)
	VALUES 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'me')), 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'site')), 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'space')), 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'website')), 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'tech')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'io')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'online')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'cloud')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'eu')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'shop')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'net')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'store')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'blog')),
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'fun'));

INSERT INTO accreditation_tld(accreditation_id,provider_instance_tld_id)
	SELECT 
		tc_id_from_name('accreditation', 'enom-identity digital limited'), 
		pit.id
	FROM provider_instance_tld pit
	JOIN tld ON pit.tld_id = tld.id
		WHERE pit.provider_instance_id = tc_id_from_name('provider_instance', 'identity digital limited -default')
		AND tld.name IN ('me','site','space','website','tech','io','online','blog','cloud','eu','shop','net','store','fun') ; 

-- 1. PROMO DATA -----------------------------------------------------------
INSERT INTO cost_domain_component 
	(cost_component_type_id,
	order_type_id, 
	accreditation_tld_id,
	period,
	value,
	currency_type_id, 
	validity,
	is_promo,
	is_promo_applied_to_1_year_only)
        SELECT
     	tc_id_from_name('cost_component_type','registry fee')
     	, CASE WHEN terc.order_type = 'create_1' THEN get_order_type_id('create', 'domain') 
     		ELSE get_order_type_id(terc.order_type, 'domain') END 
        ,get_accreditation_tld_id('enom', terc.tld)  -- ac.id 
        ,1
        ,terc.promo_regfee
        ,tc_id_from_name('currency_type', terc.currency_name) 
        ,terc.validity
        ,TRUE
        , CASE WHEN terc.order_type = 'create_1' THEN TRUE 
        	ELSE FALSE END    
    FROM temp_enom_promo terc
    WHERE TERC.is_ongoing IS TRUE; 

-- CUSTOMER DATA
CREATE TABLE "temp_enom_price_tier" (
	"LoginID" 	TEXT,
	"PlanName"	TEXT
);
\copy temp_enom_price_tier FROM 'test_finance_data/3_enom_price_tier_samples.csv' DELIMITER ',' CSV HEADER;

ALTER TABLE temp_enom_price_tier
	ADD COLUMN name TEXT,
	ADD COLUMN business_entity TEXT, 
	ADD COLUMN tier TEXT; 

UPDATE temp_enom_price_tier
SET business_entity = LOWER("LoginID"), 
	name = initcap(regexp_replace(regexp_replace("LoginID", '([0-9])([A-Za-z])', '\1 \2', 'g'),'([A-Za-z])([0-9])', '\1 \2', 'g')),
	tier = LOWER("PlanName");

INSERT INTO business_entity(name,descr) 
	SELECT tept.business_entity, 'customer'
FROM temp_enom_price_tier tept; 

INSERT INTO customer (business_entity_id, name, descr)
	SELECT tc_id_from_name('business_entity',tept.business_entity), tept.name, 'customer'
	FROM temp_enom_price_tier tept;

INSERT INTO tenant_customer (tenant_id, customer_id, customer_number)
	SELECT tc_id_from_name('tenant', 'enom'),
		tc_id_from_name('customer', tept.name), 
		FLOOR(RANDOM() * (9999999 - 1000000 + 1) + 1000000)::TEXT
	FROM temp_enom_price_tier tept;
