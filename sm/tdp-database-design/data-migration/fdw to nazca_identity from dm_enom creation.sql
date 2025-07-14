CREATE EXTENSION postgres_fdw;

CREATE  SERVER nazca_dev
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (host 'nazcadb01.dev-opensrs.bra2.tucows.systems', port '5432', dbname 'nazca_identity');

CREATE USER MAPPING FOR tucows
SERVER nazca_dev
OPTIONS (user 'nludina', password '*********');

CREATE FOREIGN TABLE contact_nazca  (
    id uuid NOT NULL,
	contact_type varchar(20) NOT NULL,
	first_name varchar(200) NULL,
	last_name varchar(200) NULL,
	email_address varchar(320) NULL,
	organization varchar(300) NULL,
	address1 varchar(255) NULL,
	address2 varchar(255) NULL,
	address3 varchar(255) NULL,
	city varchar(120) NULL,
	state varchar(120) NULL,
	postal_code varchar(30) NULL,
	country_code varchar(2) NULL,
	phone_number varchar(31) NULL,
	phone_extension varchar(15) NULL,
	fax_number varchar(31) NULL,
	creation_date timestamptz NOT NULL,
	modification_date timestamptz NOT NULL,
	reseller_id int4 NOT NULL,
	reported_active_date timestamptz NULL
)
SERVER nazca_dev
OPTIONS (schema_name 'nazca_identity',table_name 'contact');