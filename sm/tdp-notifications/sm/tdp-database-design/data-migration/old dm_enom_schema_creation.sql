
--dm_enom is staging schema for extracting Enom data

CREATE SCHEMA IF NOT EXISTS dm_enom  AUTHORIZATION --tdpadm ;
--postgres;
tucows;


--Adam table
/*CREATE TABLE IF NOT EXISTS dm_enom.identityfailures (
domainnameid int NOT NULL,
id uuid NOT NULL,
response varchar(255) NULL
);*/


-- map table for country code have only records with difference
CREATE TABLE IF NOT EXISTS  dm_enom.map_country_enom_itdp (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	"name" text NOT NULL,
	alpha2 text NOT NULL,  -- iso 3166	
	enom_alpha2 text NOT NULL,	
	CONSTRAINT country_alpha2_check CHECK ((length(alpha2) = 2)),
	CONSTRAINT country_alpha2_key UNIQUE (alpha2),	
	CONSTRAINT country_name_key UNIQUE (name),
	CONSTRAINT country_pkey PRIMARY KEY (id)
);

INSERT INTO dm_enom.map_country_enom_itdp(name, alpha2, enom_alpha2) VALUES
('United Kingdom of Great Britain and Northern Ireland', 'GB', 'UK'),
('Equatorial Guinea', 'GQ', 'EK')
ON CONFLICT DO NOTHING ;



CREATE TABLE IF NOT EXISTS  dm_enom.map_domain_status_enom_itdp (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
	itdp_id uuid NOT NULL ,
	itdp_name text NOT NULL,
	enom_name text NULL,	
	CONSTRAINT domain_status_name_key UNIQUE (itdp_name,enom_name),
	CONSTRAINT domain_status_pkey PRIMARY KEY (id)
);

INSERT INTO dm_enom.map_domain_status_enom_itdp (itdp_id,itdp_name,enom_name) 
    VALUES        
        ('24ac43cb-ff01-459a-8ed7-d1846b0404aa','Deleted','Deleted'),
	    ('c0928677-ca0b-49fd-9df7-43446f9889cc','RGP','Imminent Delete'),
	    ('24ac43cb-ff01-459a-8ed7-d1846b0404aa','Deleted','Transferred away'),
	    ('24ac43cb-ff01-459a-8ed7-d1846b0404aa','Deleted', 'Expired Transfers'),
	    ('ddfa2bed-e332-40b9-9244-2440ffa2d555','Active', 'Registered'),
		('ad4432b5-b99c-4385-ac33-477e6446216f','Expired', 'Expired'),      
		('b6131b33-1f4e-4169-93d7-6795009c3e7e','Extended RGP','Extended RGP'),
		('c0928677-ca0b-49fd-9df7-43446f9889cc','RGP','RGP'),
		('c0928677-ca0b-49fd-9df7-43446f9889cc','RGP','RGP Deactivated')
ON CONFLICT DO NOTHING ;	


CREATE TABLE IF NOT EXISTS   dm_enom.map_lock_type_enom_itdp (
	itdp_id uuid NOT NULL DEFAULT gen_random_uuid(),
	itdp_name text NOT NULL,
	enom_name text NULL,
	CONSTRAINT lock_type_name_key UNIQUE (itdp_name),
	CONSTRAINT lock_type_status_pkey PRIMARY KEY (itdp_id)
);

INSERT INTO dm_enom.map_lock_type_enom_itdp (itdp_id,itdp_name, enom_name) VALUES  
   ('3d97d496-4f1d-11e8-9bfd-02420a000396','hold', 'Hold') ,
   ('8261baeb-89fc-4020-9e05-b17158f11d9c','transfer','CustomerDomainStatus')
ON CONFLICT DO NOTHING ;




CREATE --UNLOGGED 
TABLE IF NOT EXISTS  dm_enom.DomainName_ (
	DomainNameID int  NOT NULL,
	SLD varchar(256)  NULL,
	TLD varchar(15)  NULL,
	CustomerDomainStatus varchar(15)  NULL,
	RegistrationStatus varchar(20)   NULL,
	Renew varchar(5)    NULL,
	RegPeriod smallint NULL,
	WebSite smallint  NULL,
	EncodingType char(10)  NULL,
	"hold" bit  NULL,
	RRProcessor varchar(4)  NULL,  --RRProcessor  table
	AllowParent bit  NULL,
	BulkWhois bit  NULL,
	PromotionId int NULL,
	BillingPartyID uuid NULL,
	FilterMask smallint NULL,
	InsertedDate timestamp NULL,
	SLDdotTLD varchar(272)  NULL,
	EndUserPartyId uuid NULL,
	IsPremium bit NULL,
	NextAttemptTime timestamp NULL,
	OriginalRegistrationStatus varchar(20)  NULL,
	
	-- DomainNameEpp--
	Roid varchar(89)   NULL,
	AuthInfo varchar(255)  NULL,
	svTRID varchar(64)  NULL,
	IsSync smallint  NULL,
	IsVerified bit NULL,
	LastSyncDate timestamp NULL,
	--ExtAttributes xml NULL,
	LastAuthInfoSync timestamp NULL,	
	
	--DomainExpiration--
	ExpDate timestamp  NULL,
	ExpStatusID smallint  NULL,
	StatusDate timestamp NULL,
	CreationDate timestamp NULL,
	EscrowHold bit NULL,
	EscrowDate timestamp NULL,

	-- DomainDNS--
	NSStatus varchar(20)  NULL,

	-- ExpiredDomains --
	deldate timestamp NULL,

	-- [RegistryQueueLog].[dbo].[RegistryLog]--
	TransferInDate timestamp NULL,

	-- IDNDomainName
	uname text NULL
);

CREATE --UNLOGGED  
TABLE IF NOT EXISTS  dm_enom.DomainName (
    itdp_domain_id uuid NULL,
	DomainNameID int  NOT NULL,
	SLD varchar(256)  NULL,
	TLD varchar(15)  NULL,
	CustomerDomainStatus varchar(15)  NULL,
	RegistrationStatus varchar(20)  NULL,
	Renew varchar(5)    NULL,
	RegPeriod smallint NULL,
	WebSite smallint  NULL,
	EncodingType char(10)  NULL,
	"hold" bit  NULL,
	RRProcessor varchar(4)  NULL,  --RRProcessor  table
	AllowParent bit NULL,
	BulkWhois bit  NULL,
	PromotionId int NULL,
	BillingPartyID uuid NULL,
	FilterMask smallint NULL,
	InsertedDate timestamp NULL,
	SLDdotTLD varchar(272)  NULL,
	EndUserPartyId uuid NULL,
	IsPremium bit NULL,
	NextAttemptTime timestamp NULL,
	OriginalRegistrationStatus varchar(20)  NULL,
	
	-- DomainNameEpp--
	ROID varchar(89)   NULL,
	AuthInfo varchar(255)  NULL,
	svTRID varchar(64)  NULL,
	IsSync smallint  NULL,
	IsVerified bit  NULL,
	LastSyncDate timestamp NULL,
	--ExtAttributes xml NULL,
	LastAuthInfoSync timestamp NULL,
	
	--DomainExpiration--
	ExpDate timestamp  NULL,
	ExpStatusID smallint  NULL,
	StatusDate timestamp  NULL,
	CreationDate timestamp NULL,
	EscrowHold bit NULL,
	EscrowDate timestamp NULL,

	-- DomainDNS--
	NSStatus varchar(20) NOT NULL,
	
	--
	Inserted_dm_date TIMESTAMP DEFAULT NOW(),

	-- ExpiredDomains --
	deldate timestamp NULL,

	-- [RegistryQueueLog].[dbo].[RegistryLog]--
	TransferInDate timestamp NULL,

	-- IDNDomainName
	uname text NULL,
	
	CONSTRAINT PK_DomainName PRIMARY KEY (DomainNameID)
	--CONSTRAINT FK_RRProcessor_DomName FOREIGN KEY (RRProcessor) REFERENCES NameHost.dbo.RRProcessor(RRProcessor)
);
CREATE INDEX  IF NOT EXISTS domainname_tld_idx ON dm_enom.domainname USING btree (tld);

CREATE --UNLOGGED  
TABLE IF NOT EXISTS dm_enom.NameServers_(
	Idx int NOT NULL,
	DomainNameID int NOT NULL,
	Name varchar(255)  NULL,
	IPAddress varchar(20)  NULL,
	InsertedDate timestamp NULL	
);

CREATE --UNLOGGED  
TABLE IF NOT EXISTS dm_enom.NameServers (
	itdp_domain_id uuid NULL,
	itdp_host_id uuid NULL,
	idx int not NULL ,
	--Id int NOT NULL GENERATED BY DEFAULT AS IDENTITY ,
	TLD varchar(15)  NULL,
	DomainNameID int NOT NULL,
	Name varchar(255)   NULL,
	IPAddress varchar(20)  NULL,
	InsertedDate timestamp NULL,
	CONSTRAINT PK_NameServers PRIMARY KEY (Idx)
);
CREATE INDEX  IF NOT EXISTS nameservers_tld_idx ON dm_enom.NameServers USING btree (tld);
--CREATE INDEX  IF NOT EXISTS NameServers_DomainNameID_idx ON dm_enom.NameServers USING btree (DomainNameID);


CREATE --UNLOGGED  
TABLE IF NOT EXISTS dm_enom.DomainContact (
    itdp_domain_id uuid NULL,
	Idx int  NOT NULL,
	DomainNameId int NOT NULL,
	RegContactId uuid NOT NULL,
	AdminContactId uuid NOT NULL,
	TechContactId uuid NOT NULL,
	BillContactId uuid NOT NULL,
	RegRoid varchar(100)  NULL,
	AdminRoid varchar(100)  NULL,
	TechRoid varchar(100)  NULL,
	BillRoid varchar(100) NULL,
	RaaCheck smallint NOT NULL,
	CONSTRAINT PK_DomainContact PRIMARY KEY (Idx)
	);

	CREATE --UNLOGGED  
	TABLE IF NOT EXISTS dm_enom.DomainContact_ (
	Idx int  NOT NULL,
	DomainNameId int NOT NULL,
	RegContactId uuid NOT NULL,
	AdminContactId uuid NOT NULL,
	TechContactId uuid NOT NULL,
	BillContactId uuid NOT NULL,
	RegRoid varchar(100)  NULL,
	AdminRoid varchar(100)  NULL,
	TechRoid varchar(100)  NULL,
	BillRoid varchar(100) NULL,
	RaaCheck smallint NOT NULL	
	);

	-- this table need for experiment with batches by year
/*	CREATE UNLOGGED  TABLE IF NOT EXISTS dm_enom.DomainContact__ (
	Idx int  NOT NULL,
	DomainNameId int NOT NULL,
	RegContactId uuid NOT NULL,
	AdminContactId uuid NOT NULL,
	TechContactId uuid NOT NULL,
	BillContactId uuid NOT NULL,
	RegRoid varchar(100)  NULL,
	AdminRoid varchar(100)  NULL,
	TechRoid varchar(100)  NULL,
	BillRoid varchar(100) NULL,
	RaaCheck smallint NOT NULL	
	);*/

CREATE  --UNLOGGED 
TABLE IF NOT EXISTS dm_enom.contact (
    DomainNameId int  not NULL,
	itdp_domain_id uuid NULL,	
    itdp_contact_id uuid NULL,
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	Enom_contact_id uuid not NULL,
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
	reseller_id int4  NULL,
	--TDP_city varchar(120) NULL,
	--TDP_country varchar(2) NULL,
	--TDP_data_source varchar(10) NULL,
	--TDP_is_international bool default False NULL,
	--TDP_email varchar(320) NULL,
	--TDP_address1 varchar(255) NULL,
	tld varchar(15) not   NULL,
	c_type varchar(20) NOT NULL,
	NPD boolean default false,  --No Public Data
	--TDP_contact_country_issue boolean default False  NULL,  
	--TDP_contact_city_issue boolean default False  NULL,  
	--TDP_contact_address1_issue boolean default False  NULL,  
	--TDP_contact_type uuid NULL,
	CONSTRAINT PK_contact PRIMARY KEY (id)
);
CREATE INDEX  IF NOT EXISTS contact_tld_idx ON dm_enom.contact USING btree (tld);

CREATE --UNLOGGED  
TABLE IF NOT EXISTS dm_enom.contact_ (
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
	fax_number varchar(31) NULL	,
	reseller_id int4  NULL,
	tld varchar(15)  NULL,
	c_type varchar(20)  NULL,
	DomainNameId int NULL,
	NPD boolean default false,  --No Public Data
	inserteddate timestamptz NULL
);
--CREATE INDEX  IF NOT EXISTS contact__tld_idx ON dm_enom.contact_ USING btree (tld);

CREATE --UNLOGGED  
TABLE IF NOT EXISTS dm_enom.contact_private (
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
	fax_number varchar(31) NULL	,
	reseller_id int4  NULL,
	tld varchar(15)  NULL,
	c_type varchar(20)  NULL,
	c_type_int int4  NULL,
	DomainNameId int NULL,
	NPD boolean default false  --No Public Data
);

CREATE --UNLOGGED  
TABLE  IF NOT EXISTS dm_enom.Customers (
	PartyID UUID NOT NULL,
	LoginID varchar(20)  NOT NULL,
	Password varchar(20) NOT NULL,
	AuthQuestionType varchar(15)  NOT NULL,
	AuthQuestionAnswer varchar(50)  NOT NULL,
	Creation timestamptz NOT NULL,
	Reseller smallint NOT NULL,
	DomainNameCount int NOT NULL,
	Account char(11)   NOT NULL,
	ParentAccount char(11)  NOT NULL,
	Site varchar(4)  NULL,
	AcceptTerms bit NOT NULL,
	ParentControl bit NOT NULL,
	AccountStatus smallint NULL,
	AccountStatusTimeStamp timestamptz NULL,
	NoService bit NULL,
	URL varchar(150)  NULL,
	AcceptUSTerms bit NULL,
	IsPWencrypted bit NULL,
	EmailAddress_Contact text  NULL,
	Refs varchar(50)  NULL,
	ParkingEnabled bit NOT NULL,
	NoServicePlan smallint NULL,
	ParkingEnabledDate timestamptz NULL,
	AccountType smallint NOT NULL,
	ResellerAgreement bit NULL,
	InsertedDate timestamptz NULL,
	ParentPartyID UUID NULL,
	BypassCVV2 bit NULL,
	SourceID varchar(50)  NULL,
	UserSessionID varchar(50)  NULL,
	PricingParentPartyID UUID NULL,
	EncryptedPwd BYTEA NULL,
	EncryptionTypeID smallint NULL,
	ContactId UUID NULL,
	PendingAsync bit NULL,
	ConsentID int NULL,
	CONSTRAINT PK_Customers PRIMARY KEY (PartyID)
	);

CREATE --UNLOGGED 
TABLE  IF NOT EXISTS dm_enom.Party (
	PartyID UUID NOT NULL,
	OrganizationName text  NULL,
	JobTitle text  NULL,
	FName text  NOT NULL,
	LName text  NOT NULL,
	Address1 text  NULL,
	Address2 text  NULL,
	City text  NULL,
	StateProvince text  NULL,
	StateProvinceChoice varchar(20)  NULL,
	PostalCode varchar(15)  NULL,
	Country text  NULL,
	Phone varchar(20)  NOT NULL,
	Fax varchar(20)  NULL,
	EmailAddress text  NOT NULL,
	DateTimeChanged timestamptz NULL,
	Account char(11)  NULL,
	PhoneExt varchar(10)  NULL,
	OwnerPartyID UUID NULL,
	InsertedDate timestamptz NOT NULL,
	ImportID int NULL,
	Handle varchar(20)  NULL,
	Validated bit NULL,
	ValidationDate timestamptz NULL,
	CONSTRAINT PK_Party PRIMARY KEY (PartyID)
);

