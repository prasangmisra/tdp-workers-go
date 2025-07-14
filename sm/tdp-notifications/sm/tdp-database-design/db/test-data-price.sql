-- special cases to pay different currency for particular orders default for tenant_customer.currency
INSERT INTO finance_setting (type_id, tenant_customer_id, provider_instance_tld_id, value_text, validity)
VALUES
    (tc_id_from_name('finance_setting_type', 'tenant_customer.provider_instance_tld.specific_currency')
    , NULL
    , NULL
    , 'USD'
    , tstzrange('2024-01-01 UTC', 'infinity')); 

INSERT INTO finance_setting (type_id,  tenant_customer_id, provider_instance_tld_id, value_text, validity)
VALUES
    (tc_id_from_name('finance_setting_type', 'tenant_customer.provider_instance_tld.specific_currency')
    , get_tenant_customer_id('enom', 'Arvixe')
	, get_provider_instance_tld_id(get_accreditation_tld_id('enom'::TEXT, 'au'))
    , 'AUD'
    , tstzrange('2024-01-01 UTC', 'infinity')); 

-- tier for prices 
INSERT INTO product_customer_tier (tenant_customer_id, product_tier_type_id, start_date)
	SELECT tc.id ,
		tc_id_from_name('product_tier_type', tept.tier), 
		TIMESTAMPTZ '2024-01-01 00:00:00 UTC'
	FROM tenant_customer tc
	JOIN temp_enom_price_tier tept ON tc.customer_id = tc_id_from_name('customer',tept.name)
	WHERE tc.tenant_id = tc_id_from_name('tenant', 'enom'); 

-- 1. TIER PRICE DATA 
CREATE TABLE "temp_enom_tierprice_restore" (
	"TLD"  						TEXT
	,"ProdType"  				TEXT
	,"ProdDesc"  				TEXT
	,"RGPProcessSupported"  	TEXT
	,"BaseCost"  				TEXT
	,"Currency"  				TEXT
	,"ProviderFeesUSD"  		TEXT
	,"CostUSD"  				TEXT
	,"DefaultResellerPrice"  	TEXT
	,"DefaultRetailPrice"  		TEXT
);
\copy temp_enom_tierprice_restore FROM 'test_finance_data/4_eNom_TLD_RGP_Cost_DefaultPrices.csv' DELIMITER ',' CSV HEADER;

ALTER TABLE temp_enom_tierprice_restore
    ADD COLUMN tld TEXT, 
    ADD COLUMN order_type TEXT, 
    ADD COLUMN currency_abbreviation TEXT, 
    ADD COLUMN price INTEGER; 

UPDATE temp_enom_tierprice_restore
	SET tld = LOWER("TLD"),   
	order_type = 'redeem',-- per TRANSACTION 
	currency_abbreviation = 'USD', 
	price = CAST(CAST(COALESCE(NULLIF(REPLACE(REPLACE(REPLACE("DefaultResellerPrice", ',', ''), '$', ''), '"', ''), ''), '0') AS NUMERIC) * 100 AS INTEGER)
WHERE "DefaultResellerPrice" != 'NULL'; 

INSERT INTO domain_price_tier
	(tenant_id,
	price_type_id,
	order_type_id,
    product_tier_type_id, 
	value,
	PERIOD,
	period_type_id,
	currency_type_id,
	validity,
	accreditation_tld_id)
	SELECT 
		tc_id_from_name('tenant','enom')
		, tc_id_from_name('price_type','tier')
		, get_order_type_id('redeem', 'domain')
        , ptt.id
		, tetr.price
		, 1
		, tc_id_from_name('period_type','transaction')
		, tc_id_from_name('currency_type',tetr.currency_abbreviation)
		, tstzrange(DATE_TRUNC('year', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE, 'infinity', '[]')
		,get_accreditation_tld_id('enom', tetr.tld)	
	FROM temp_enom_tierprice_restore tetr 
	JOIN product_tier_type ptt ON TRUE
	WHERE get_accreditation_tld_id('enom', tetr.tld) IS NOT NULL;

CREATE TABLE "temp_enom_tierprice_others" (
	"TLD" TEXT,
	"ProdType" TEXT,
	"ProdDesc" TEXT,
	"Years" TEXT,
	"BaseCostBeforeICANNFees" TEXT,
	"Currency" TEXT,
	"ProviderFeesUSD" TEXT,
	"CostBeforeICANNFeesUSD" TEXT,
	"ICANNFees," TEXT,
	"Essencial" TEXT,
	"Advanced" TEXT,
	"Premium" TEXT,
	"Enterprise" TEXT
); 
\copy temp_enom_tierprice_others FROM 'test_finance_data/5_eNom_TLD_others_Cost_DefaultPrices.csv' DELIMITER ',' CSV HEADER;

ALTER TABLE temp_enom_tierprice_others
    ADD COLUMN tld TEXT, 
    ADD COLUMN order_type TEXT, 
    ADD COLUMN currency_abbreviation TEXT, 
    ADD COLUMN essencial INTEGER, 
	ADD COLUMN advanced INTEGER,
	ADD COLUMN premium INTEGER,
	ADD COLUMN enterprise INTEGER; 

UPDATE temp_enom_tierprice_others
	SET tld = LOWER("TLD"); 

UPDATE temp_enom_tierprice_others
	SET order_type = CASE 
		WHEN "ProdDesc" = 'Register' THEN 'create'
		WHEN "ProdDesc" = 'Renew' THEN 'renew'
		WHEN "ProdDesc" = 'Transfer' THEN 'transfer_in'
		WHEN "ProdDesc" = 'Restore (RGP)' THEN 'redeem' -- per TRANSACTION 
		WHEN "ProdDesc" = 'Restore (extended RGP)' THEN 'redeem+' 
	END; 

UPDATE temp_enom_tierprice_others
	SET currency_abbreviation = "Currency";  

UPDATE temp_enom_tierprice_others
	SET essencial = CAST(CAST(COALESCE(NULLIF(REPLACE(REPLACE(REPLACE("Essencial", ',', ''), '$', ''), '"', ''), ''), '0') AS NUMERIC) * 100 AS INTEGER),
	advanced = CAST(CAST(COALESCE(NULLIF(REPLACE(REPLACE(REPLACE("Advanced", ',', ''), '$', ''), '"', ''), ''), '0') AS NUMERIC) * 100 AS INTEGER),
	premium = CAST(CAST(COALESCE(NULLIF(REPLACE(REPLACE(REPLACE("Premium", ',', ''), '$', ''), '"', ''), ''), '0') AS NUMERIC) * 100 AS INTEGER),
	enterprise = CAST(CAST(COALESCE(NULLIF(REPLACE(REPLACE(REPLACE("Enterprise", ',', ''), '$', ''), '"', ''), ''), '0') AS NUMERIC) * 100 AS INTEGER);

INSERT INTO domain_price_tier --3016 tld * 3 order_type * 4 tier 
	(tenant_id,
	price_type_id,
	order_type_id,
    product_tier_type_id, 
	value,
	PERIOD,
	period_type_id,
	currency_type_id,
	validity,
	accreditation_tld_id)
	SELECT 
		tc_id_from_name('tenant','enom')
		,tc_id_from_name('price_type','tier')
		,ot.id 
		,ptt.id
		, CASE WHEN ptt.name = 'essential' THEN teto.essencial
			WHEN ptt.name = 'advanced' THEN teto.advanced
			WHEN ptt.name = 'premium' THEN teto.premium
			WHEN ptt.name = 'enterprise' THEN teto.enterprise
			END 
		, 1
		, CASE WHEN ot.name IN ('create','renew') THEN tc_id_from_name('period_type','year')
			ELSE tc_id_from_name('period_type','transaction')
			END 
		, tc_id_from_name('currency_type',teto.currency_abbreviation)
		, tstzrange(DATE_TRUNC('year', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE, 'infinity', '[]')
		, get_accreditation_tld_id('enom', teto.tld)
	FROM temp_enom_tierprice_others teto
	JOIN v_order_type ot ON ot."name" = teto.order_type AND ot.product_id = tc_id_from_name('product', 'domain')
	JOIN product_tier_type ptt ON TRUE 
	WHERE "Years" = '1'
		AND get_accreditation_tld_id('enom', teto.tld) IS NOT NULL;

-- 2. PREMIUM  goes to domain_premium_margin with NULL fields for some parameters

-- 3. CUSTOM & 4. CUSTOM - COST+ PRICE DATA 
CREATE TABLE "temp_enom_custom" (
	"login_id"				TEXT
	,"tld"					TEXT
	,"custom_cost_plus"		TEXT
	,"custom"				TEXT
); 

\copy temp_enom_custom FROM 'test_finance_data/6_costPlusAll_20240626.csv' DELIMITER ',' CSV HEADER;

ALTER TABLE temp_enom_custom
	ADD COLUMN custom1 TEXT, 
    ADD COLUMN custom_cost_plus2 INTEGER,
    ADD COLUMN custom2 INTEGER, 
	ADD COLUMN currency TEXT,
	ADD COLUMN tld2 TEXT,
	ADD COLUMN login_id2 TEXT;

UPDATE temp_enom_custom
	SET custom1 = REPLACE(REPLACE(custom, ',', ''), '(', ''),
	tld2 = LOWER(tld),
	login_id2 = LOWER(login_id); 

UPDATE temp_enom_custom
	SET 
	custom_cost_plus2 = CASE WHEN custom_cost_plus != 'NULL' THEN CAST(CAST(REPLACE(custom_cost_plus, '$', '') AS NUMERIC) * 100 AS INTEGER)
	ELSE 0 END, 
	custom2 = CASE WHEN custom != 'NULL' THEN CAST(CAST(REPLACE(custom1, '$', '') AS NUMERIC) * 100 AS INTEGER)
	ELSE 0 END,
	currency = 'USD';

INSERT INTO business_entity(name,descr) -- 97
	SELECT DISTINCT tec.login_id2, 'customer+'
FROM temp_enom_custom tec
WHERE tec.login_id2 NOT IN (SELECT "name" FROM business_entity); 

INSERT INTO customer (business_entity_id, name, descr) -- 97
	SELECT DISTINCT-- tc_id_from_name('business_entity',tec.login_id2), tec.login_id2, 'customer+'
		be.id, tec.login_id2, 'customer+'
	FROM temp_enom_custom tec 
	JOIN business_entity be ON be.id = tc_id_from_name('business_entity',tec.login_id2)
	WHERE be.descr = 'customer+';

INSERT INTO tenant_customer (tenant_id, customer_id, customer_number)
	SELECT tc_id_from_name('tenant', 'enom'),
		c.id,
		FLOOR(RANDOM() * (9999999 - 1000000 + 1) + 1000000)::TEXT
	FROM customer c 
	WHERE c.descr = 'customer+';

-- fake tier information 
INSERT INTO product_customer_tier (tenant_customer_id, product_tier_type_id, start_date)
    SELECT 
        tc.id, 
        CASE 
            WHEN c.name LIKE '[a-gA-G]%' THEN tc_id_from_name('product_tier_type','essential')
            WHEN c.name LIKE '[h-nH-N]%' THEN tc_id_from_name('product_tier_type','enterprise')
            WHEN c.name LIKE '[o-uO-U]%' THEN tc_id_from_name('product_tier_type','premium')
            ELSE tc_id_from_name('product_tier_type','advanced')
        END,
        TIMESTAMPTZ '2024-01-01 00:00:00 UTC'
    FROM tenant_customer tc
    JOIN customer c ON c.id = tc.customer_id
    WHERE tc.tenant_id = tc_id_from_name('tenant', 'enom')
        AND c.descr = 'customer+'; 

INSERT INTO domain_price_custom -- 3. CUSTOM --  276
	(tenant_customer_id,
	price_type_id,
	order_type_id,
	accreditation_tld_id,
	value,
	PERIOD,
	period_type_id, 
	currency_type_id,
	validity,
	is_promo_cost_supported)
	SELECT DISTINCT tc.id 
		,tc_id_from_name('price_type','custom') 
		,vot.id
		,get_accreditation_tld_id('enom', tec.tld2)
		,tec.custom2
		,1
		, CASE WHEN vot.name IN ('create','renew') THEN tc_id_from_name('period_type','year')
			ELSE tc_id_from_name('period_type','transaction')
			END 
		, tc_id_from_name('currency_type', tec.currency)
		,tstzrange(DATE_TRUNC('year', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE, 'infinity', '[]') 
		,TRUE	
	FROM tenant_customer tc	
	JOIN customer c ON c.id = tc.customer_id
	JOIN v_order_type vot ON TRUE
	JOIN temp_enom_custom tec ON c.name = tec.login_id2
	WHERE tc.tenant_id = tc_id_from_name('tenant', 'enom')
		AND c.descr = 'customer+'
		AND vot.product_name = 'domain'
		AND tec.custom2 != 0
		AND tec.tld2 IN (SELECT name FROM tld); 

INSERT INTO domain_price_custom -- 4. CUSTOM-COST+ --  67992
	(tenant_customer_id,
	price_type_id,
	order_type_id,
	accreditation_tld_id,
	value,
	PERIOD,
	period_type_id, 
	currency_type_id,
	validity,
	is_promo_cost_supported)
	SELECT DISTINCT tc.id 
		,tc_id_from_name('price_type','custom - cost+') 
		,vot.id
		,get_accreditation_tld_id('enom', tec.tld2)
		,tec.custom_cost_plus2
		,1
		, CASE WHEN vot.name IN ('create','renew') THEN tc_id_from_name('period_type','year')
			ELSE tc_id_from_name('period_type','transaction')
			END 
		, tc_id_from_name('currency_type', tec.currency)
		,tstzrange(DATE_TRUNC('year', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE, 'infinity', '[]') 
		,FALSE	
	FROM tenant_customer tc	
	JOIN customer c ON c.id = tc.customer_id
	JOIN v_order_type vot ON TRUE
	JOIN temp_enom_custom tec ON c.name = tec.login_id2
	WHERE tc.tenant_id = tc_id_from_name('tenant', 'enom')
		AND c.descr = 'customer+'
		AND vot.product_name = 'domain'
		AND tec.custom_cost_plus2 != 0
		AND tec.tld2 IN (SELECT name FROM tld);

-- 8. custom - premium
CREATE TABLE "temp_enom_custom_premium" (
	"Property"			TEXT
	,"LoginID"			TEXT
	,"TLD"				TEXT
	,"ResellerTier1"	TEXT
	,"ResellerTier2"	TEXT
	,"ResellerTier3"	TEXT
	,"ResellerTier4"	TEXT
); 

\copy temp_enom_custom_premium FROM 'test_finance_data/7_enom_custom_premium.csv' DELIMITER ',' CSV HEADER;

ALTER TABLE temp_enom_custom_premium
	ADD COLUMN int1 REAL, 
	ADD COLUMN int2 REAL,
	ADD COLUMN int3 REAL, 
	ADD COLUMN int4 REAL;

UPDATE temp_enom_custom_premium
	SET int1 = CAST("ResellerTier1" AS REAL), 
	int2 = CAST("ResellerTier2" AS REAL),
	int3 = CAST("ResellerTier3" AS REAL),
	int4 = CAST("ResellerTier4" AS REAL);

-- Add indexes to improve performance
CREATE INDEX idx_temp_enom_custom_premium_int1 ON temp_enom_custom_premium (int1);
CREATE INDEX idx_temp_enom_custom_premium_int2 ON temp_enom_custom_premium (int2);
CREATE INDEX idx_temp_enom_custom_premium_int3 ON temp_enom_custom_premium (int3);
CREATE INDEX idx_temp_enom_custom_premium_int4 ON temp_enom_custom_premium (int4);

-- customer DATA
INSERT INTO business_entity(name,descr) -- 97
	SELECT DISTINCT tecp."LoginID", 'customer_premium'
FROM temp_enom_custom_premium tecp
WHERE tecp."LoginID" NOT IN (SELECT "name" FROM business_entity);

INSERT INTO customer (business_entity_id, name, descr) -- 97
	SELECT DISTINCT-- tc_id_from_name('business_entity',tec.login_id2), tec.login_id2, 'customer+'
		be.id, tecp."LoginID", 'customer_premium'
	FROM temp_enom_custom_premium tecp 
	JOIN business_entity be ON be.id = tc_id_from_name('business_entity',tecp."LoginID")
	WHERE be.descr = 'customer_premium'
		AND tecp."LoginID" NOT IN (SELECT "name" FROM customer) ;	

INSERT INTO tenant_customer (tenant_id, customer_id, customer_number)
	SELECT tc_id_from_name('tenant', 'enom'),
		c.id,
		FLOOR(RANDOM() * (999999999 - 100000000 + 1) + 100000000)::TEXT
	FROM customer c 
	WHERE c.descr = 'customer_premium'
     AND c.name NOT IN ('Helloloc','Indexcor');

INSERT INTO tld(name,registry_id, type_id) --5
	VALUES   
	('airforce', tc_id_from_name('registry', 'identity digital limited registry'), tc_id_from_name('tld_type','generic')), 
	('rehab',  tc_id_from_name('registry', 'identity digital limited registry'), tc_id_from_name('tld_type','generic')), 
	('republican',  tc_id_from_name('registry', 'identity digital limited registry'), tc_id_from_name('tld_type','generic')), 
	('video',  tc_id_from_name('registry', 'identity digital limited registry'), tc_id_from_name('tld_type','generic')), 
	('gives',  tc_id_from_name('registry', 'identity digital limited registry'), tc_id_from_name('tld_type','generic')); 

INSERT INTO provider_instance_tld(provider_instance_id,tld_id)
	VALUES 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'airforce')), 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'rehab')), 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'republican')), 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'video')), 
	(tc_id_from_name('provider_instance', 'identity digital limited -default'), tc_id_from_name('tld', 'gives'));

INSERT INTO accreditation_tld(accreditation_id,provider_instance_tld_id)
		SELECT 
			tc_id_from_name('accreditation', 'enom-identity digital limited'), 
			pit.id
		FROM provider_instance_tld pit
		JOIN tld ON pit.tld_id = tld.id
			WHERE pit.provider_instance_id = tc_id_from_name('provider_instance', 'identity digital limited -default')
			AND tld.name IN ('airforce','gives','rehab','republican','video') ; 

INSERT INTO domain_premium_margin (product_cost_range_id, price_type_id, tenant_customer_id, value, start_date, accreditation_tld_id)
	SELECT 
		UNNEST(ARRAY [(SELECT id FROM product_cost_range cr WHERE cr.product_id = tc_id_from_name('product','domain') AND value @> numrange(1, 10000, '[)')) ,
                (SELECT id FROM product_cost_range cr WHERE cr.product_id = tc_id_from_name('product','domain') AND value @> numrange(10000, 50000, '[)')),
                (SELECT id FROM product_cost_range cr WHERE cr.product_id = tc_id_from_name('product','domain') AND value @> numrange(50000, 150000, '[)')), 
                (SELECT id FROM product_cost_range cr WHERE cr.product_id = tc_id_from_name('product','domain') AND value @> numrange(150000, null, '[)'))])   
        ,tc_id_from_name('price_type','custom - premium')
        ,tc.id
        ,unnest(array[ tecp.int1, tecp.int2, tecp.int3, tecp.int4])
        ,TIMESTAMPTZ '2024-01-01 00:00:00 UTC'
        ,get_accreditation_tld_id('enom', tecp."TLD")
	FROM temp_enom_custom_premium tecp 
	JOIN customer c ON c.name = tecp."LoginID"
	JOIN tenant_customer tc	ON c.id = tc.customer_id 
		AND tc.tenant_id = tc_id_from_name('tenant', 'enom')
		AND tecp."TLD" IN (SELECT name FROM tld);

-- 5.1 PROMO - ALL type: fixed_price 
INSERT INTO domain_price_tenant_promo -- 5.1 PROMO - ALL type: fixed_price BLOG ALL-tiers?
	(tenant_id,
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
		tc_id_from_name('tenant', 'enom')
		,tc_id_from_name('price_type',tep.price_type)
        ,tc_id_from_name('promo_type','fixed price')
		,CASE WHEN tep.order_type LIKE 'create%' 
			THEN get_order_type_id('create', 'domain')
			ELSE get_order_type_id(tep.order_type, 'domain') END  
		,get_accreditation_tld_id('enom', tep.tld)	
		,tep.promo_price
		,1
		,CASE WHEN tep.order_type IN ('create_1','create','renew') THEN tc_id_from_name('period_type','year')
			ELSE tc_id_from_name('period_type','transaction')
			END 
		, tc_id_from_name('currency_type', tep.currency_name)
		,tstzrange(DATE_TRUNC('year', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE, 'infinity', '[]') 
        ,CASE WHEN tep.order_type = 'create_1' THEN TRUE ELSE FALSE END
        FROM temp_enom_promo tep
	WHERE tep.price_type = 'promo - all'
		AND tep."Platforms" = 'Enom'
		AND tep.tld = 'blog';

INSERT INTO domain_price_tenant_promo -- 5.1 PROMO - ALL type: fixed_price CLOUD only advanced tier
	(tenant_id,
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
		tc_id_from_name('tenant', 'enom')
		,tc_id_from_name('price_type',tep.price_type)
        ,tc_id_from_name('promo_type','fixed price')
		,CASE WHEN tep.order_type LIKE 'create%' 
			THEN get_order_type_id('create', 'domain')
			ELSE get_order_type_id(tep.order_type, 'domain') END  
		,get_accreditation_tld_id('enom', tep.tld)	
		,tep.promo_price
		,1
		,CASE WHEN tep.order_type IN ('create_1','create','renew') THEN tc_id_from_name('period_type','year')
			ELSE tc_id_from_name('period_type','transaction')
			END 
		, tc_id_from_name('currency_type', tep.currency_name)
		,tstzrange(DATE_TRUNC('year', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE, 'infinity', '[]') 
        ,CASE WHEN tep.order_type = 'create_1' THEN TRUE ELSE FALSE END
	FROM temp_enom_promo tep
	JOIN product_tier_type tt ON TRUE
	WHERE tep.price_type = 'promo - all'
		AND tep."Platforms" = 'Enom'
		AND tep.tld = 'cloud'
		AND tt.name = 'advanced'; 

-- 6.1 PROMO - SIGNUP type: fixed_price
INSERT INTO domain_price_tenant_promo -- 6.1 PROMO - SIGNUP type: fixed_price ALL tiers 
	(tenant_id,
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
		tc_id_from_name('tenant', 'enom')
		,tc_id_from_name('price_type',tep.price_type)
        ,tc_id_from_name('promo_type','fixed price')
		,CASE WHEN tep.order_type LIKE 'create%' 
			THEN get_order_type_id('create', 'domain')
			ELSE get_order_type_id(tep.order_type, 'domain') END  
		,get_accreditation_tld_id('enom', tep.tld)	
		,tep.promo_price
		,1
		,CASE WHEN tep.order_type IN ('create_1','create','renew') THEN tc_id_from_name('period_type','year')
			ELSE tc_id_from_name('period_type','transaction')
			END 
		, tc_id_from_name('currency_type', tep.currency_name)
		,tstzrange(DATE_TRUNC('year', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE, 'infinity', '[]') 
        ,CASE WHEN tep.order_type = 'create_1' THEN TRUE ELSE FALSE END
	FROM temp_enom_promo tep
	WHERE tep.price_type = 'promo - signup'
		AND tep."Platforms" = 'Enom'
		AND tep.is_ongoing = TRUE; 
    
-- 7.1 PROMO - CUSTOM type: fixed_price fake data 

INSERT INTO domain_price_customer_promo -- 7.1 PROMO - CUSTOM type: fixed_price
	(tenant_customer_id,
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
	  SELECT DISTINCT 
		get_tenant_customer_id('enom', 'catalyst2')
		,tc_id_from_name('price_type',tep.price_type)
        ,tc_id_from_name('promo_type','fixed price')
		,CASE WHEN tep.order_type LIKE 'create%' 
			THEN get_order_type_id('create', 'domain')
			ELSE get_order_type_id(tep.order_type, 'domain') END  
		,get_accreditation_tld_id('enom', tep.tld)	
		,tep.promo_price
		,1
		,CASE WHEN tep.order_type IN ('create_1','create','renew') THEN tc_id_from_name('period_type','year')
			ELSE tc_id_from_name('period_type','transaction')
			END 
		,tc_id_from_name('currency_type',tep.currency_name)  
		,tstzrange(DATE_TRUNC('year', CURRENT_DATE)::TIMESTAMP WITH TIME ZONE, 'infinity', '[]') 
        ,CASE WHEN tep.order_type = 'create_1' THEN TRUE ELSE FALSE END
	FROM temp_enom_promo tep
    JOIN accreditation_tld act ON act.id = get_accreditation_tld_id('enom', tep.tld)
  
	WHERE tep.price_type = 'promo - custom'
		AND tep."Platforms" = 'Enom'
		AND tep.is_ongoing = TRUE
		AND promo_price IS NOT NULL
		AND tep.order_type != 'create_1'; 
