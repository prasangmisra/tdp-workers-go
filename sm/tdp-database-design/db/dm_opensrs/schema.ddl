--dm_opensrs is staging schema for extracting Enom data
CREATE SCHEMA IF NOT EXISTS dm_opensrs;    

-- map table for country code have only records with difference
CREATE TABLE IF NOT EXISTS  dm_opensrs.map_country_enom_itdp (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	"name" text NOT NULL,
	alpha2 text NOT NULL,  -- iso 3166	
	enom_alpha2 text NOT NULL,	
	CONSTRAINT country_alpha2_check CHECK ((length(alpha2) = 2)),
	CONSTRAINT country_alpha2_key UNIQUE (alpha2),	
	CONSTRAINT country_name_key UNIQUE (name),
	CONSTRAINT country_pkey PRIMARY KEY (id)
);

/*CREATE TABLE IF NOT EXISTS  dm_opensrs.map_domain_status_enom_itdp (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
	itdp_id uuid NOT NULL ,
	itdp_name text NOT NULL,
	enom_name text NULL,	
	CONSTRAINT domain_status_name_key UNIQUE (itdp_name,enom_name),
	CONSTRAINT domain_status_pkey PRIMARY KEY (id)
);*/


/*CREATE TABLE IF NOT EXISTS   dm_opensrs.map_lock_type_enom_itdp (
	itdp_id uuid NOT NULL DEFAULT gen_random_uuid(),
	itdp_name text NOT NULL,
	enom_name text NULL,
	CONSTRAINT lock_type_name_key UNIQUE (itdp_name),
	CONSTRAINT lock_type_status_pkey PRIMARY KEY (itdp_id)
);*/


CREATE TABLE IF NOT EXISTS  dm_opensrs.DomainName (
    itdp_domain_id uuid NULL,
	DomainNameID int  NOT NULL,	
	TLD varchar(20)  NULL,	
	RegistrationStatus varchar(20)  NULL,
	Renew varchar(5)    NULL,
	RegPeriod smallint NULL,	
	EncodingType char(15)  NULL,
	lock_hold bit  NULL,
	lock_delete bit  NULL,
	lock_transfer bit  NULL,
	lock_update bit  NULL,	
	
	Reseller_id int NULL,	
	SLDdotTLD varchar(272)  NULL,

	ROID varchar(100)   NULL,
	AuthInfo varchar(255)  NULL,
	
	
	ExpDate timestamp  NULL,	
	CreationDate timestamp NULL,
	CreationDate_NSI timestamp NULL,
	UPDATEDATE timestamp  NULL,		
	--
	Inserted_dm_date TIMESTAMP DEFAULT NOW(),

	deldate timestamp NULL,	
	TransferInDate timestamp NULL,
	-- IDNDomainName
	uname text NULL,	
	CONSTRAINT PK_DomainName PRIMARY KEY (DomainNameID)

);
CREATE INDEX  IF NOT EXISTS domainname_tld_idx ON dm_opensrs.domainname USING btree (tld);


CREATE TABLE IF NOT EXISTS dm_opensrs.NameServers (
    source_nameserver_id serial4 NOT NULL,
    domain_nameserver_id int  NULL,
	itdp_domain_id uuid NULL,
	itdp_host_id uuid NULL,
	idx int not NULL ,	
	TLD varchar(20)  NULL,
	DomainNameID int NOT NULL,
	Name varchar(255)   NULL,
	IP varchar(45)  NULL,
	IPV6 varchar(45)  NULL,
	CONSTRAINT PK_NameServers PRIMARY KEY (source_nameserver_id)
);
CREATE INDEX  IF NOT EXISTS nameservers_tld_idx ON dm_opensrs.NameServers USING btree (tld);

CREATE  TABLE IF NOT EXISTS dm_opensrs.contact (
    DomainNameId int  not NULL,
	itdp_domain_id uuid NULL,	
    itdp_contact_id uuid NULL,
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	Enom_contact_id int not NULL,
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
	postal_code varchar(32) NULL,
	country_code varchar(6) NULL,
	phone_number varchar(31) NULL,
	phone_extension varchar(15) NULL,
	fax_number varchar(31) NULL,
	reseller_id int4  NULL,	
	tld varchar(20) not   NULL,
	c_type varchar(20)  NULL,
	NPD boolean default false,  --No Public Data
	is_private boolean default false,	
	handl TEXT,
	CONSTRAINT PK_contact PRIMARY KEY (id)
);
CREATE INDEX  IF NOT EXISTS contact_tld_idx ON dm_opensrs.contact USING btree (tld);




CREATE TABLE IF NOT EXISTS  dm_opensrs.DomainName_ (
   	DomainNameID int  NOT NULL,	
	TLD varchar(20)  NULL,	
	RegistrationStatus varchar(20)  NULL,
	Renew varchar(5)    NULL,
	RegPeriod smallint NULL,	
	EncodingType char(15)  NULL,
	lock_hold bit  NULL,
	lock_delete bit  NULL,
	lock_transfer bit  NULL,
	lock_update bit  NULL,	
	
	Reseller_id int NULL,	
	SLDdotTLD varchar(272)  NULL,

	ROID varchar(100)   NULL,
	AuthInfo varchar(255)  NULL,
	
	
	ExpDate timestamp  NULL,	
	CreationDate timestamp NULL,
	CreationDate_NSI timestamp NULL,
	UPDATEDATE timestamp  NULL,		
	--
	Inserted_dm_date TIMESTAMP DEFAULT NOW(),

	deldate timestamp NULL,	
	TransferInDate timestamp NULL,
	-- IDNDomainName
	uname text NULL
);



CREATE TABLE IF NOT EXISTS dm_opensrs.NameServers_ (
    domain_nameserver_id int NULL,	
	idx int not NULL ,	
	DomainNameID int NOT NULL,
	Name varchar(255)   NULL,
	IP varchar(45)  NULL,
	IPV6 varchar(45)  NULL
);


CREATE  TABLE IF NOT EXISTS dm_opensrs.contact_ (
    DomainNameId int  not NULL,	
	Enom_contact_id int not NULL,
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
	postal_code varchar(32) NULL,
	country_code varchar(6) NULL,
	phone_number varchar(31) NULL,
	phone_extension varchar(15) NULL,
	fax_number varchar(31) NULL,
	reseller_id int4  NULL,	
	tld varchar(20) not   NULL,
	c_type varchar(20)  NULL,
	NPD boolean default false,  --No Public Data
	is_private boolean default false,	
	handl TEXT
);