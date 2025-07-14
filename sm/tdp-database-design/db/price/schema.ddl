-- table: promo_type
-- description: there are three types of promotions; percent, fied discount, fixed price;  
-- 				for product_type domain only fixed price is used; 

CREATE TABLE  promo_type (
    id 			UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    "name" 		TEXT NOT NULL,
    descr 		TEXT NOT NULL,
    UNIQUE ("name")
);
-- indexes for promo_type table
CREATE INDEX idx_promo_type_name ON  promo_type(name);

--
-- table: price_type
-- description: this table has types of price that can be submitted for the approval

CREATE TABLE  price_type (
	id 				UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
	"name" 			TEXT NOT NULL,
	descr 			TEXT NOT NULL,
	overrides 		UUID[] NULL,
	level 			INTEGER NOT NULL DEFAULT 0, 
	UNIQUE ("name")
);
-- indexes for price_type table
CREATE INDEX idx_price_type_id ON price_type(id);
CREATE INDEX idx_price_type_name ON  price_type(name);

--
-- table: product_cost_range
-- description: stores ranges or costs 

CREATE TABLE  product_cost_range (
	id 			UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
	product_id 	UUID NOT NULL REFERENCES product,
	value 		NUMRANGE NOT NULL,
	UNIQUE(product_id, value)
);
-- indexes for product_cost_range table
CREATE INDEX idx_product_cost_range_product_id ON  product_cost_range(product_id);

--
-- table: domain_premium_margin stores custom premium margins ( needs tenant_customer_id and accreditation_tld_id)
-- description: stores margines for premium prices; 
-- where tenant_customer_id IS NULL then it is a defaut value 

CREATE TABLE  domain_premium_margin (
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

-- indexes for domain_premium_margin table
CREATE INDEX idx_domain_premium_margin_product_cost_range_id ON  domain_premium_margin(product_cost_range_id);
CREATE INDEX idx_domain_premium_margin_tenant_customer_id ON  domain_premium_margin(tenant_customer_id);
CREATE INDEX idx_domain_premium_margin_accreditation_tld_id ON  domain_premium_margin(accreditation_tld_id);
CREATE INDEX idx_domain_premium_margin_price_type_id ON  domain_premium_margin(price_type_id);

--
-- table: product_tier_type
-- description: this table has list of tiers to which customer can belong

CREATE TABLE  product_tier_type(
	id 			UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
	product_id	UUID NOT NULL REFERENCES product,
	"name" 		TEXT NOT NULL,
	UNIQUE (name, product_id)
);
-- indexes for product_tier_type table
CREATE INDEX idx_product_tier_type_name ON  product_tier_type(name);
CREATE INDEX idx_product_tier_type_product_id ON  product_tier_type(product_id);

--
-- table: product_customer_tier
-- description: this table stores the information about tenant_customer assigned tier

CREATE TABLE  product_customer_tier(
	id 						UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
	tenant_customer_id 		UUID NOT NULL REFERENCES tenant_customer, 
	product_tier_type_id 	UUID NOT NULL REFERENCES product_tier_type,
	start_date				TIMESTAMPTZ NOT NULL,
	UNIQUE(tenant_customer_id, 
		product_tier_type_id,
		start_date)
) INHERITS (class.audit,class.soft_delete);

-- indexes for product_customer_tier table
CREATE INDEX idx_product_customer_tier_tenant_customer_id ON  product_customer_tier(tenant_customer_id);
CREATE INDEX idx_product_customer_tier_product_tier_type_id ON  product_customer_tier(product_tier_type_id);

-- 
-- table: product_price_strategy
-- description: stores at what time there is a info for that price_type

CREATE TABLE  product_price_strategy(
	id 						UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
	product_id				UUID NOT NULL REFERENCES product, 
	price_type_id			UUID NOT NULL REFERENCES price_type, 
	level					INTEGER NOT NULL, 	
	iteration_order			INTEGER NOT NULL,
	UNIQUE(product_id, price_type_id)
) INHERITS (class.audit, class.soft_delete);

-- 
-- table: domain_price_tier
-- description: stores tier prices 

CREATE TABLE  domain_price_tier(
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

-- indexes for domain_price_tier table
CREATE INDEX idx_domain_price_tier_tenant_id ON  domain_price_tier(tenant_id);
CREATE INDEX idx_domain_price_tier_price_type_id ON  domain_price_tier(price_type_id);
CREATE INDEX idx_domain_price_tier_order_type_id ON  domain_price_tier(order_type_id);
CREATE INDEX idx_domain_price_tier_product_tier_type_id ON  domain_price_tier(product_tier_type_id);
CREATE INDEX idx_domain_price_tier_currency_type_id ON  domain_price_tier(currency_type_id);
CREATE INDEX idx_domain_price_tier_accreditation_tld_id ON  domain_price_tier(accreditation_tld_id);
CREATE INDEX idx_domain_price_tier_period_type_id ON  domain_price_tier(period_type_id);

-- 
-- table: domain_price_custom
-- description: stores custom & custom_cost+ prices 

CREATE TABLE  domain_price_custom(
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

-- indexes for domain_price_custom table
CREATE INDEX idx_domain_price_custom_tenant_customer_id ON  domain_price_custom(tenant_customer_id);
CREATE INDEX idx_domain_price_custom_price_type_id ON  domain_price_custom(price_type_id);
CREATE INDEX idx_domain_price_custom_order_type_id ON  domain_price_custom(order_type_id);
CREATE INDEX idx_domain_price_custom_currency_type_id ON  domain_price_custom(currency_type_id);
CREATE INDEX idx_domain_price_custom_accreditation_tld_id ON  domain_price_custom(accreditation_tld_id);
CREATE INDEX idx_domain_price_custom_period_type_id ON  domain_price_custom(period_type_id);

-- 
-- table: domain_price_tenant_promo
-- description: stores promo all and promo sign-up that has not been assined to a customer

CREATE TABLE  domain_price_tenant_promo(
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

-- indexes for domain_price_tenant_promo table
CREATE INDEX idx_domain_price_tenant_promo_tenant_id ON  domain_price_tenant_promo(tenant_id);
CREATE INDEX idx_domain_price_tenant_promo_price_type_id ON  domain_price_tenant_promo(price_type_id);
CREATE INDEX idx_domain_price_tenant_promo_order_type_id ON  domain_price_tenant_promo(order_type_id);
CREATE INDEX idx_domain_price_tenant_promo_promo_type_id ON  domain_price_tenant_promo(promo_type_id);
CREATE INDEX idx_domain_price_tenant_promo_accreditation_tld_id ON  domain_price_tenant_promo(accreditation_tld_id);
CREATE INDEX idx_domain_price_tenant_promo_period_type_id ON  domain_price_tenant_promo(period_type_id);
CREATE INDEX idx_domain_price_tenant_promo_currency_type_id ON  domain_price_tenant_promo(currency_type_id);



-- 
-- table: domain_price_customer_promo
-- description: stores promo custom and promo- signup prices assigned to customers 

CREATE TABLE  domain_price_customer_promo(
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

-- indexes for domain_price_customer_promo table
CREATE INDEX idx_domain_price_customer_promo_tenant_customer_id ON  domain_price_customer_promo(tenant_customer_id);
CREATE INDEX idx_domain_price_customer_promo_price_type_id ON  domain_price_customer_promo(price_type_id);
CREATE INDEX idx_domain_price_customer_promo_order_type_id ON  domain_price_customer_promo(order_type_id);
CREATE INDEX idx_domain_price_customer_promo_promo_type_id ON  domain_price_customer_promo(promo_type_id);
CREATE INDEX idx_domain_price_customer_promo_accreditation_tld_id ON  domain_price_customer_promo(accreditation_tld_id);
CREATE INDEX idx_domain_price_customer_promo_period_type_id ON  domain_price_customer_promo(period_type_id);
CREATE INDEX idx_domain_price_customer_promo_currency_type_id ON  domain_price_customer_promo(currency_type_id);


-- 
-- table: repeating_charge_type 
-- description: stores various types or reparating fees  
-- A price for a repeating charge, tied to a range of products, that should get billed to a reseller account -- even where that charge may not be tied to a particular product or cost.

CREATE TABLE  repeating_charge_type (
	id 			UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    "name" 		TEXT NOT NULL,
    descr 		TEXT NOT NULL,
    UNIQUE ("name")
);
-- indexes for repeating_charge_type table
CREATE INDEX idx_repeating_charge_type_name ON  repeating_charge_type(name);
 
-- 
-- table: domain_price_repeating_charge
-- description: stores repeating charge prices information 
	
CREATE TABLE  domain_price_repeating_charge(
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

-- indexes for domain_price_repeating_charge table
CREATE INDEX idx_domain_price_repeating_charge_repeating_charge_type_id ON  domain_price_repeating_charge(repeating_charge_type_id);
CREATE INDEX idx_domain_price_repeating_charge_product_id ON  domain_price_repeating_charge(product_id);
CREATE INDEX idx_domain_price_repeating_charge_price_type_id ON  domain_price_repeating_charge(price_type_id);
CREATE INDEX idx_domain_price_repeating_charge_tenant_customer_id ON  domain_price_repeating_charge(tenant_customer_id);
CREATE INDEX idx_domain_price_repeating_charge_period_type_id ON  domain_price_repeating_charge(period_type_id);
CREATE INDEX idx_domain_price_repeating_charge_currency_type_id ON  domain_price_repeating_charge(currency_type_id);
