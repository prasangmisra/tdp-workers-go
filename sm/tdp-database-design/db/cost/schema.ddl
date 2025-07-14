--                                                              -- removed table finance_configuration
-- table: period_type
-- stores various units of measure: month, day, week, year , quarter, transaction  

CREATE TABLE  period_type(
  id 				                UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
	"name" 			              TEXT NOT NULL,
	UNIQUE ("name")
)INHERITS (class.audit);
CREATE INDEX idx_period_type_name ON  period_type("name");

--
-- table: order_type_period_type
-- stores connection between order_type and period_type

CREATE TABLE  order_type_period_type(
	id 				                UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
	order_type_id 			      UUID NOT NULL REFERENCES order_type,
  period_type_id            UUID NOT NULL REFERENCES period_type, 
	UNIQUE (order_type_id, period_type_id)
);
CREATE INDEX idx_order_type_period_type_order_type_id ON  order_type_period_type(order_type_id);
CREATE INDEX idx_order_type_period_type_period_type_id ON  order_type_period_type(period_type_id);

--
-- table: currency_exchange_rate
-- description: this table list the possible currency_exchange_rate & its conversion coefficients
-- all given in cents

CREATE TABLE currency_exchange_rate( 
	id 				                UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
	currency_type_id          UUID NOT NULL REFERENCES currency_type, 
  value 			              DECIMAL(19, 4) NOT NULL,
  validity 		              TSTZRANGE NOT NULL CHECK (NOT isempty(validity))
	--EXCLUDE USING gist (COALESCE(currency_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
  --                  validity WITH &&)
)INHERITS (class.audit);
CREATE INDEX idx_exchange_rate_currency_type_id ON  currency_exchange_rate(currency_type_id);

--
-- table: cost_type
-- description: this table has types of cost that can be submitted for the approval

CREATE TABLE  cost_type (
	id 			    UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
	"name" 		  TEXT NOT NULL,
	descr 		  TEXT not NULL,
	UNIQUE ("name")
)INHERITS (class.audit);
CREATE INDEX idx_cost_type_name ON  cost_type("name");

--
-- table: cost_component_type 
-- description: lists components of cost and full cost for domain
-- is_periodic - CHARGED BY YEAR; is_static FIXED; DOES NOT DEPEND ON OTHER FEE 

CREATE TABLE  cost_component_type (
  id 						                      UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
  "name" 					                    TEXT NOT NULL,
  cost_type_id                        UUID NOT NULL REFERENCES cost_type,
  is_periodic			                    BOOLEAN NOT NULL DEFAULT TRUE,
  is_percent                          BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE ("name")
)INHERITS (class.audit);
CREATE INDEX idx_cost_component_type_name ON  cost_component_type("name");
CREATE INDEX idx_cost_component_type_cost_type_id ON  cost_component_type(cost_type_id);
CREATE INDEX idx_cost_component_type_is_periodic ON  cost_component_type(is_periodic);
CREATE INDEX idx_cost_component_type_is_percent ON  cost_component_type(is_percent);

--
-- table: cost_product_strategy 
-- description: This table stores information about different cost strategies associated with 
-- products. Each record represents a unique strategy that can be applied to a product, including
--  details such as strategy type, description, and any relevant parameters or conditions.

CREATE TABLE  cost_product_strategy (
  id                                  UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
  order_type_id                       UUID NOT NULL REFERENCES order_type, 
  cost_component_type_id              UUID NOT NULL REFERENCES cost_component_type,
  calculation_sequence                INTEGER NOT NULL, 
  is_in_total_cost                    BOOLEAN NOT NULL DEFAULT TRUE,	
  UNIQUE (order_type_id, cost_component_type_id)
)INHERITS (class.audit);
CREATE INDEX idx_product_cost_strategy_order_type_id ON  cost_product_strategy(order_type_id);
CREATE INDEX idx_product_cost_strategy_cost_component_type_id ON  cost_product_strategy(cost_component_type_id);

--
-- table: cost_product_component 
-- description:  nothing can be added to this table; 
-- records can be added to child tables only; each product will have its own XXX_cost_component table; 

CREATE TABLE cost_product_component (
  id 		                              UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY,
  cost_component_type_id              UUID NOT NULL REFERENCES cost_component_type,
  order_type_id                       UUID REFERENCES order_type,
  period                              INTEGER DEFAULT 1,
  period_type_id                      UUID DEFAULT tc_id_from_name('period_type', 'year') REFERENCES period_type,             
  value                               DECIMAL(19, 4) NOT NULL,
  currency_type_id                    UUID DEFAULT tc_id_from_name('currency_type', 'USD') REFERENCES currency_type,
  is_promo                            BOOLEAN NOT NULL DEFAULT FALSE,
  is_promo_applied_to_1_year_only     BOOLEAN DEFAULT NULL,
  is_rebate                           BOOLEAN DEFAULT NULL,
  validity                            TSTZRANGE NOT NULL CHECK (NOT isempty(validity)),
  EXCLUDE USING gist (COALESCE(cost_component_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            COALESCE(order_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            period WITH =,
            period_type_id WITH =,
            COALESCE(currency_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            bool_to_value(is_promo::BOOLEAN) WITH =,
            validity WITH &&)
)INHERITS (class.audit);

CREATE INDEX idx_product_cost_component_cost_component_type_id ON  cost_product_component(cost_component_type_id);
CREATE INDEX idx_product_cost_component_order_type_id ON  cost_product_component(order_type_id);
CREATE INDEX idx_product_cost_component_currency_type_id ON  cost_product_component(currency_type_id);

CREATE TABLE cost_domain_component (
  accreditation_tld_id                    UUID REFERENCES accreditation_tld, 
  FOREIGN KEY (cost_component_type_id)    REFERENCES cost_component_type,
  FOREIGN KEY (order_type_id)             REFERENCES order_type,
  FOREIGN KEY (currency_type_id)          REFERENCES currency_type, 
  FOREIGN KEY (period_type_id)            REFERENCES period_type,
  PRIMARY KEY (id),
  EXCLUDE USING gist (COALESCE(cost_component_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            COALESCE(accreditation_tld_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            COALESCE(order_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            period WITH =,
            period_type_id WITH =,
            COALESCE(currency_type_id, '00000000-0000-0000-0000-000000000000'::UUID) WITH =, 
            bool_to_value(is_promo::BOOLEAN) WITH =,
            validity WITH &&)
) INHERITS (cost_product_component);

CREATE INDEX idx_cost_domain_component_cost_component_type_id ON  cost_domain_component(cost_component_type_id);
CREATE INDEX idx_cost_domain_component_accreditation_tld_id ON  cost_domain_component(accreditation_tld_id);
CREATE INDEX idx_cost_domain_component_order_type_id ON  cost_domain_component(order_type_id);
CREATE INDEX idx_cost_domain_component_currency_type_id ON  cost_domain_component(currency_type_id);

-- table: stock_keeping_unit
-- description: stores inventory for all products for all brands 
-- example: sku23255431

CREATE TABLE  stock_keeping_unit(
  id                       	  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  sku                         TEXT NOT NULL DEFAULT generate_sku(),  
  order_type_period_type_id   UUID NOT NULL REFERENCES order_type_period_type, -- product_id, order_type_id, period_type_id
  UNIQUE (order_type_period_type_id)
)INHERITS (class.audit);

CREATE INDEX idx_stock_keeping_unit_order_type_period_type_id ON  stock_keeping_unit(order_type_period_type_id);

-- table: stock_keeping_unit_domain inherits stock_keeping_unit
-- description: stores inventory for domains for all brands 
-- example: sku23255431

CREATE TABLE  stock_keeping_unit_domain(
  id                       	    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  accreditation_tld_id          UUID NOT NULL REFERENCES accreditation_tld, 
  FOREIGN KEY (order_type_period_type_id)   REFERENCES order_type_period_type, 
  UNIQUE (accreditation_tld_id, order_type_period_type_id)
) INHERITS (stock_keeping_unit, class.audit, class.soft_delete);

CREATE INDEX idx_domain_stock_keeping_unit_accreditation_tld_id ON  stock_keeping_unit_domain(accreditation_tld_id);
CREATE INDEX idx_domain_stock_keeping_unit_order_type_period_type_id ON  stock_keeping_unit_domain(order_type_period_type_id);

/*
  * The following section focuses on grandfathered domains that may be stored in buckets and requires logical 
  * structuring and thorough documentation for further development.
  */

--
-- table: sld_filter_type
-- description: stores regular expression rules or filter like length or exact word that indicated by registry that is part of premium domain and particular 
-- premium bucket

/* 
CREATE TABLE  sld_filter_type(
	id                      UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY, 
  descr                   TEXT,
  filter                  TEXT NOT NULL, 
  value_INTEGER           INTEGER,
  value_TEXT              TEXT,
  value_timestamptz       timestamptz,
  value_timestamptz_range TSTZRANGE,
  value_BOOLEANean           BOOL,
  value_TEXT_list         TEXT[],
  value_INTEGER_list      INT[] -- ranges better 
)INHERITS (class.audit);
CREATE INDEX idx_sld_filter_type_filter ON  sld_filter_type(filter);

--
-- table: non_standard_bucket_type
-- description: stores description of premium buckets for registry-tld that don't support premium extension check 

CREATE TABLE  non_standard_bucket_type(
	id                  UUID NOT NULL DEFAULT gen_random_UUID() PRIMARY KEY, 
  descr               TEXT,
  registry_id         UUID NOT NULL REFERENCES registry, 
  tld_id              UUID NOT NULL REFERENCES tld,
  sld_filter_type_id  UUID [] NOT NULL,-- REFERENCES sld_filter_type,
  UNIQUE(registry_id,tld_id)      
)INHERITS (class.audit);     
CREATE INDEX idx_non_standard_bucket_type_registry_id ON  non_standard_bucket_type(registry_id);
CREATE INDEX idx_non_standard_bucket_type_tld_id ON  non_standard_bucket_type(tld_id);
*/


