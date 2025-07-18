-- dm_ascio is staging schema for extracting Ascio data
CREATE SCHEMA IF NOT EXISTS dm_ascio AUTHORIZATION tucows;

-- table deleted_domains_rgp: to store all the deleted domains in RDP status 
CREATE TABLE dm_ascio.deleted_domains_rgp (
	id int4 NULL,
	account varchar(50) NULL,
	handle varchar(50) NULL,
	"domain" varchar(128) NULL,
	nicprovider varchar(50) NULL,
	status varchar(128) NULL,
	expires timestamptz NULL,
	rgp_period timestamptz NULL,
	vendortag varchar(50) NULL,
	objectid varchar(50) NULL
);


-- table all_domains: to store all domains in all the statuses 
CREATE TABLE dm_ascio.all_domains (
	domain_handle varchar(50) NULL,
	domain_status varchar(50) NULL,
	domain_created timestamptz NULL,
	domain_updated timestamptz NULL,
	domain_expires timestamptz NULL,
	domain_activated timestamptz NULL,
	domain_deleted timestamptz NULL,
	domain_owner varchar(128) NULL,
	domain_nicprovider varchar(128) NULL,
	domain_vendortag varchar(128) NULL,
	domain_name varchar(128) NULL,
	domain_tld varchar(128) NULL,
	domain_registrationperiod varchar(128) NULL,
	domain_encodingtype varchar(128) NULL,
	domain_emailforward varchar(128) NULL,
	domain_domainpurpose varchar(128) NULL,
	domain_authorization varchar(128) NULL,
	domain_expiryconfirmationid varchar(128) NULL,
	domain_renewperiod varchar(128) NULL,
	domain_trademarkname varchar(128) NULL,
	domain_trademarkcountry varchar(128) NULL,
	domain_trademarkdate varchar(128) NULL,
	domain_trademarkidentifier varchar(128) NULL,
	domain_trademarktype varchar(128) NULL,
	domain_trademarkcontact varchar(128) NULL,
	domain_trademarkdocumentationlanguage varchar(128) NULL,
	domain_queuetype varchar(128) NULL,
	domain_trademarkcontactlanguage varchar(128) NULL,
	domain_localpresence varchar(128) NULL,
	domain_asciodns varchar(128) NULL,
	domain_customerreference_handle varchar(128) NULL,
	customerreference_externalid varchar(128) NULL,
	customerreference_description varchar(128) NULL,
	domain_domaincomment varchar(128) NULL,
	domain_trademarkregdate varchar(128) NULL,
	domain_trademarksecondcontact varchar(128) NULL,
	domain_dnsseckey1_handle varchar(128) NULL,
	dnsseckey1_keytag varchar(128) NULL,
	dnsseckey1_digestalgorithm varchar(128) NULL,
	dnsseckey1_digesttype varchar(128) NULL,
	dnsseckey1_digest varchar(128) NULL,
	dnsseckey1_keytype varchar(128) NULL,
	dnsseckey1_protocol varchar(128) NULL,
	dnsseckey1_keyalgorithm varchar(128) NULL,
	dnsseckey1_publickey varchar(128) NULL,
	domain_trademarkthirdcontact varchar(128) NULL,
	domain_dnsseckey2_handle varchar(128) NULL,
	dnsseckey2_keytag varchar(128) NULL,
	dnsseckey2_digestalgorithm varchar(128) NULL,
	dnsseckey2_digesttype varchar(128) NULL,
	dnsseckey2_digest varchar(128) NULL,
	dnsseckey2_keytype varchar(128) NULL,
	dnsseckey2_protocol varchar(128) NULL,
	dnsseckey2_keyalgorithm varchar(128) NULL,
	dnsseckey2_publickey varchar(128) NULL,
	domain_dnsseckey3_handle varchar(128) NULL,
	dnsseckey3_keytag varchar(128) NULL,
	dnsseckey3_digestalgorithm varchar(128) NULL,
	dnsseckey3_digesttype varchar(128) NULL,
	dnsseckey3_digest varchar(128) NULL,
	dnsseckey3_keytype varchar(128) NULL,
	dnsseckey3_protocol varchar(128) NULL,
	dnsseckey3_keyalgorithm varchar(128) NULL,
	dnsseckey3_publickey varchar(128) NULL,
	domain_dnsseckey4_handle varchar(128) NULL,
	dnsseckey4_keytag varchar(128) NULL,
	dnsseckey4_digestalgorithm varchar(128) NULL,
	dnsseckey4_digesttype varchar(128) NULL,
	dnsseckey4_digest varchar(128) NULL,
	dnsseckey4_keytype varchar(128) NULL,
	dnsseckey4_protocol varchar(128) NULL,
	dnsseckey4_keyalgorithm varchar(128) NULL,
	dnsseckey4_publickey varchar(128) NULL,
	domain_dnsseckey5_handle varchar(128) NULL,
	dnsseckey5_keytag varchar(128) NULL,
	dnsseckey5_digestalgorithm varchar(128) NULL,
	dnsseckey5_digesttype varchar(128) NULL,
	dnsseckey5_digest varchar(128) NULL,
	dnsseckey5_keytype varchar(128) NULL,
	dnsseckey5_protocol varchar(128) NULL,
	dnsseckey5_keyalgorithm varchar(128) NULL,
	dnsseckey5_publickey varchar(128) NULL,
	domain_domaintype varchar(128) NULL,
	domain_own_handle varchar(128) NULL,
	own_orgname varchar(128) NULL,
	own_organizationnumber varchar(128) NULL,
	own_legalstatus varchar(128) NULL,
	own_address1 varchar(128) NULL,
	own_address2 varchar(128) NULL,
	own_city varchar(128) NULL,
	own_postalcode varchar(128) NULL,
	own_state varchar(128) NULL,
	own_country varchar(128) NULL,
	own_email varchar(128) NULL,
	own_phone varchar(50) NULL,
	own_fax varchar(50) NULL,
	own_contactname varchar(128) NULL,
	own_organizationinceptiondate varchar(128) NULL,
	own_nexuscategory varchar(128) NULL,
	own_vatnumber varchar(128) NULL,
	own_type varchar(128) NULL,
	own_details varchar(128) NULL,
	domain_tec_handle varchar(128) NULL,
	tec_firstname varchar(128) NULL,
	tec_lastname varchar(128) NULL,
	tec_email varchar(128) NULL,
	tec_phone varchar(50) NULL,
	tec_fax varchar(50) NULL,
	tec_orgname varchar(128) NULL,
	tec_address1 varchar(128) NULL,
	tec_address2 varchar(128) NULL,
	tec_state varchar(128) NULL,
	tec_postalcode varchar(128) NULL,
	tec_city varchar(128) NULL,
	tec_country varchar(128) NULL,
	tec_organizationnumber varchar(128) NULL,
	tec_type varchar(128) NULL,
	tec_details varchar(128) NULL,
	domain_adm_handle varchar(128) NULL,
	adm_firstname varchar(128) NULL,
	adm_lastname varchar(128) NULL,
	adm_email varchar(128) NULL,
	adm_phone varchar(50) NULL,
	adm_fax varchar(50) NULL,
	adm_orgname varchar(128) NULL,
	adm_address1 varchar(128) NULL,
	adm_address2 varchar(128) NULL,
	adm_state varchar(128) NULL,
	adm_postalcode varchar(128) NULL,
	adm_city varchar(128) NULL,
	adm_country varchar(128) NULL,
	adm_organizationnumber varchar(128) NULL,
	adm_type varchar(128) NULL,
	adm_details varchar(128) NULL,
	domain_bil_handle varchar(128) NULL,
	bil_firstname varchar(128) NULL,
	bil_lastname varchar(128) NULL,
	bil_email varchar(128) NULL,
	bil_phone varchar(50) NULL,
	bil_fax varchar(50) NULL,
	bil_orgname varchar(128) NULL,
	bil_address1 varchar(128) NULL,
	bil_address2 varchar(128) NULL,
	bil_state varchar(128) NULL,
	bil_postalcode varchar(128) NULL,
	bil_city varchar(128) NULL,
	bil_country varchar(128) NULL,
	bil_organizationnumber varchar(128) NULL,
	bil_type varchar(128) NULL,
	bil_details varchar(128) NULL,
	domain_res_handle varchar(128) NULL,
	res_firstname varchar(128) NULL,
	res_lastname varchar(128) NULL,
	res_email varchar(128) NULL,
	res_phone varchar(50) NULL,
	res_fax varchar(50) NULL,
	res_orgname varchar(128) NULL,
	res_address1 varchar(128) NULL,
	res_address2 varchar(128) NULL,
	res_state varchar(128) NULL,
	res_postalcode varchar(128) NULL,
	res_city varchar(128) NULL,
	res_country varchar(128) NULL,
	res_organizationnumber varchar(128) NULL,
	res_type varchar(128) NULL,
	res_details varchar(128) NULL,
	domain_ns1_handle varchar(128) NULL,
	ns1_hostname varchar(128) NULL,
	ns1_ipaddress varchar(128) NULL,
	"ns1_tech-contact" varchar(128) NULL,
	"ns1_admin-contact" varchar(128) NULL,
	ns1_ipv6address varchar(128) NULL,
	ns1_details varchar(128) NULL,
	domain_ns2_handle varchar(128) NULL,
	ns2_hostname varchar(128) NULL,
	ns2_ipaddress varchar(128) NULL,
	"ns2_tech-contact" varchar(128) NULL,
	"ns2_admin-contact" varchar(128) NULL,
	ns2_ipv6address varchar(128) NULL,
	ns2_details varchar(128) NULL,
	domain_ns3_handle varchar(128) NULL,
	ns3_hostname varchar(128) NULL,
	ns3_ipaddress varchar(128) NULL,
	"ns3_tech-contact" varchar(128) NULL,
	"ns3_admin-contact" varchar(128) NULL,
	ns3_ipv6address varchar(128) NULL,
	ns3_details varchar(128) NULL,
	domain_ns4_handle varchar(128) NULL,
	ns4_hostname varchar(128) NULL,
	ns4_ipaddress varchar(128) NULL,
	"ns4_tech-contact" varchar(128) NULL,
	"ns4_admin-contact" varchar(128) NULL,
	ns4_ipv6address varchar(128) NULL,
	ns4_details varchar(128) NULL,
	domain_ns5_handle varchar(128) NULL,
	ns5_hostname varchar(128) NULL,
	ns5_ipaddress varchar(128) NULL,
	"ns5_tech-contact" varchar(128) NULL,
	"ns5_admin-contact" varchar(128) NULL,
	ns5_ipv6address varchar(128) NULL,
	ns5_details varchar(128) NULL,
	domain_ns6_handle varchar(128) NULL,
	ns6_hostname varchar(128) NULL,
	ns6_ipaddress varchar(128) NULL,
	"ns6_tech-contact" varchar(128) NULL,
	"ns6_admin-contact" varchar(128) NULL,
	ns6_ipv6address varchar(128) NULL,
	ns6_details varchar(128) NULL,
	domain_ns7_handle varchar(128) NULL,
	ns7_hostname varchar(128) NULL,
	ns7_ipaddress varchar(128) NULL,
	"ns7_tech-contact" varchar(128) NULL,
	"ns7_admin-contact" varchar(128) NULL,
	ns7_ipv6address varchar(128) NULL,
	ns7_details varchar(128) NULL,
	domain_ns8_handle varchar(128) NULL,
	ns8_hostname varchar(128) NULL,
	ns8_ipaddress varchar(128) NULL,
	"ns8_tech-contact" varchar(128) NULL,
	"ns8_admin-contact" varchar(128) NULL,
	ns8_ipv6address varchar(128) NULL,
	ns8_details varchar(128) NULL,
	domain_ns9_handle varchar(128) NULL,
	ns9_hostname varchar(128) NULL,
	ns9_ipaddress varchar(128) NULL,
	"ns9_tech-contact" varchar(128) NULL,
	"ns9_admin-contact" varchar(128) NULL,
	ns9_ipv6address varchar(128) NULL,
	ns9_details varchar(128) NULL,
	domain_ns10_handle varchar(128) NULL,
	ns10_hostname varchar(128) NULL,
	ns10_ipaddress varchar(128) NULL,
	"ns10_tech-contact" varchar(128) NULL,
	"ns10_admin-contact" varchar(128) NULL,
	ns10_ipv6address varchar(128) NULL,
	ns10_details varchar(128) NULL,
	domain_ns11_handle varchar(128) NULL,
	ns11_hostname varchar(128) NULL,
	ns11_ipaddress varchar(128) NULL,
	"ns11_tech-contact" varchar(128) NULL,
	"ns11_admin-contact" varchar(128) NULL,
	ns11_ipv6address varchar(128) NULL,
	ns11_details varchar(128) NULL,
	domain_ns12_handle varchar(128) NULL,
	ns12_hostname varchar(128) NULL,
	ns12_ipaddress varchar(128) NULL,
	"ns12_tech-contact" varchar(128) NULL,
	"ns12_admin-contact" varchar(128) NULL,
	ns12_ipv6address varchar(128) NULL,
	ns12_details varchar(128) NULL,
	domain_ns13_handle varchar(128) NULL,
	ns13_hostname varchar(128) NULL,
	ns13_ipaddress varchar(128) NULL,
	"ns13_tech-contact" varchar(128) NULL,
	"ns13_admin-contact" varchar(128) NULL,
	ns13_ipv6address varchar(128) NULL,
	ns13_details varchar(128) NULL,
	domain_masternameserverip varchar(128) NULL,
	domain_privacyproxytype varchar(128) NULL,
	domain_privacymask varchar(128) NULL,
	domain_maskownerentity_handle varchar(128) NULL,
	maskownerentity_orgname varchar(128) NULL,
	maskownerentity_organizationnumber varchar(128) NULL,
	maskownerentity_legalstatus varchar(128) NULL,
	maskownerentity_address1 varchar(128) NULL,
	maskownerentity_address2 varchar(128) NULL,
	maskownerentity_city varchar(128) NULL,
	maskownerentity_postalcode varchar(128) NULL,
	maskownerentity_state varchar(128) NULL,
	maskownerentity_country varchar(128) NULL,
	maskownerentity_email varchar(128) NULL,
	maskownerentity_phone varchar(128) NULL,
	maskownerentity_fax varchar(128) NULL,
	maskownerentity_contactname varchar(128) NULL,
	maskownerentity_organizationinceptiondate varchar(128) NULL,
	maskownerentity_nexuscategory varchar(128) NULL,
	maskownerentity_vatnumber varchar(128) NULL,
	maskownerentity_type varchar(128) NULL,
	maskownerentity_details varchar(128) NULL,
	domain_maskadm_handle varchar(128) NULL,
	maskadm_firstname varchar(128) NULL,
	maskadm_lastname varchar(128) NULL,
	maskadm_email varchar(128) NULL,
	maskadm_phone varchar(128) NULL,
	maskadm_fax varchar(128) NULL,
	maskadm_orgname varchar(128) NULL,
	maskadm_address1 varchar(128) NULL,
	maskadm_address2 varchar(128) NULL,
	maskadm_state varchar(128) NULL,
	maskadm_postalcode varchar(128) NULL,
	maskadm_city varchar(128) NULL,
	maskadm_country varchar(128) NULL,
	maskadm_organizationnumber varchar(128) NULL,
	maskadm_type varchar(128) NULL,
	maskadm_details varchar(128) NULL,
	domain_masktec_handle varchar(128) NULL,
	masktec_firstname varchar(128) NULL,
	masktec_lastname varchar(128) NULL,
	masktec_email varchar(128) NULL,
	masktec_phone varchar(128) NULL,
	masktec_fax varchar(128) NULL,
	masktec_orgname varchar(128) NULL,
	masktec_address1 varchar(128) NULL,
	masktec_address2 varchar(128) NULL,
	masktec_state varchar(128) NULL,
	masktec_postalcode varchar(128) NULL,
	masktec_city varchar(128) NULL,
	masktec_country varchar(128) NULL,
	masktec_organizationnumber varchar(128) NULL,
	masktec_type varchar(128) NULL,
	masktec_details varchar(128) NULL,
	domain_maskbil_handle varchar(128) NULL,
	maskbil_firstname varchar(128) NULL,
	maskbil_lastname varchar(128) NULL,
	maskbil_email varchar(128) NULL,
	maskbil_phone varchar(128) NULL,
	maskbil_fax varchar(128) NULL,
	maskbil_orgname varchar(128) NULL,
	maskbil_address1 varchar(128) NULL,
	maskbil_address2 varchar(128) NULL,
	maskbil_state varchar(128) NULL,
	maskbil_postalcode varchar(128) NULL,
	maskbil_city varchar(128) NULL,
	maskbil_country varchar(128) NULL,
	maskbil_organizationnumber varchar(128) NULL,
	maskbil_type varchar(128) NULL,
	maskbil_details varchar(128) NULL,
	domain_lockobject varchar(128) NULL,
	domain_disclosesocialdata varchar(128) NULL,
	totalrowcount int8 NULL
);

-- table domain_filtered: to store all the reklevant domains - status Active & Deleted in RGP period; 
CREATE TABLE dm_ascio.domain_filtered as 
	select *  
	FROM dm_ascio.all_domains
	WHERE FALSE;

-- table domain: 
CREATE TABLE dm_ascio."domain" (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	source_domain_id serial4 NOT NULL,
	"name" varchar(200) NOT NULL,
	auth_info varchar(200) NULL,
	roid varchar(100) NULL,
	ry_created_date timestamptz NOT NULL,
	ry_expiry_date timestamptz NOT NULL,
	ry_updated_date timestamptz NULL,
	ry_transfered_date timestamptz NULL,
	deleted_date timestamptz NULL,
	expiry_date timestamptz NOT NULL,
	auto_renew bool DEFAULT true NOT NULL,
	secdns_max_sig_life int4 NULL,
	idn_uname varchar(100) NULL,
	idn_lang varchar(100) NULL,
	source_ascio_domain_id varchar(100) NULL,
	source_ascio_reseller_id varchar(100) NULL,
	CONSTRAINT domain_pkey PRIMARY KEY (source_domain_id)
);

-- table domain_lock:
CREATE TABLE dm_ascio.domain_lock (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	domain_id int4 NULL,
	"lock" varchar(100) NOT NULL,
	type_id uuid NULL,
	is_internal bool DEFAULT false NOT NULL,
	created_date timestamptz DEFAULT now() NULL,
	expiry_date timestamptz NULL,
	CONSTRAINT domain_lock_check CHECK (((expiry_date IS NULL) OR ((expiry_date IS NOT NULL) AND is_internal))),
	CONSTRAINT domain_lock_domain_id_type_id_is_internal_key UNIQUE (domain_id, type_id, is_internal),
	CONSTRAINT domain_lock_pkey PRIMARY KEY (id),
	CONSTRAINT domain_lock_domain_id_fkey FOREIGN KEY (domain_id) REFERENCES dm_ascio."domain"(source_domain_id)
);

-- table domain_rgp_status:
CREATE TABLE dm_ascio.domain_rgp_status (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	domain_id int4 NOT NULL,
	status_id uuid NULL,
	status varchar(50) NOT NULL,
	created_date timestamptz DEFAULT now() NULL,
	expiry_date timestamptz NOT NULL,
	CONSTRAINT domain_rgp_status_pkey PRIMARY KEY (id)
);

-- table host:
CREATE TABLE dm_ascio.host (
	source_host_id serial4 NOT NULL,
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	domain_id int4 NULL,
	tags _text NULL,
	metadata jsonb DEFAULT '{}'::jsonb NULL,
	domain_ns_handle text NOT NULL,
	CONSTRAINT host_pkey PRIMARY KEY (source_host_id)
);

-- table host_addr:
CREATE TABLE dm_ascio.host_addr (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	host_id int4 NOT NULL,
	address inet NULL,
	CONSTRAINT host_addr_pkey PRIMARY KEY (id),
	CONSTRAINT host_addr_host_id_fkey FOREIGN KEY (host_id) REFERENCES dm_ascio.host(source_host_id)
);

-- table domain_host:
CREATE TABLE dm_ascio.domain_host (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	domain_id int4 NOT NULL,
	host_id int4 NOT NULL,
	CONSTRAINT domain_host_domain_id_host_id_key UNIQUE (domain_id, host_id),
	CONSTRAINT domain_host_pkey PRIMARY KEY (id),
	CONSTRAINT domain_host_domain_id_fkey FOREIGN KEY (domain_id) REFERENCES dm_ascio."domain"(source_domain_id),
	CONSTRAINT domain_host_host_id_fkey FOREIGN KEY (host_id) REFERENCES dm_ascio.host(source_host_id)
);

-- table contact:
CREATE TABLE dm_ascio.contact (
	source_contact_id uuid DEFAULT gen_random_uuid() NOT NULL,
	type_id uuid NULL,
	"type" text NOT NULL,
	title text NULL,
	org_reg text NULL,
	org_vat text NULL,
	org_duns text NULL,
	email text NULL,
	phone text NULL,
	fax text NULL,
	country text NOT NULL,
	"language" text NULL,
	tags text NULL,
	documentation text NULL,
	phone_ext text NULL,
	fax_ext text NULL,
	contact_handle text NOT NULL,
	CONSTRAINT contact_pkey PRIMARY KEY (source_contact_id)
);

-- table contact_postal:
CREATE TABLE dm_ascio.contact_postal (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	source_contact_id uuid NOT NULL,
	is_international bool DEFAULT false NOT NULL,
	first_name text NULL,
	last_name text NULL,
	org_name text NULL,
	address1 text NOT NULL,
	address2 text NULL,
	address3 text NULL,
	city text NOT NULL,
	postal_code text NULL,
	state text NULL,
	CONSTRAINT contact_postal_contact_id_is_international_key UNIQUE (source_contact_id, is_international),
	CONSTRAINT contact_postal_pkey PRIMARY KEY (id),
	CONSTRAINT contact_postal_source_contact_id_fkey FOREIGN KEY (source_contact_id) REFERENCES dm_ascio.contact(source_contact_id)
);

-- table domain_contact:
CREATE TABLE dm_ascio.domain_contact (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	source_domain_id int4 NOT NULL,
	source_contact_id uuid NOT NULL,
	domain_contact_type_id uuid NULL,
	domain_contact_type text NOT NULL,
	is_local_presence bool DEFAULT false NOT NULL,
	is_privacy_proxy bool DEFAULT false NOT NULL,
	is_private bool DEFAULT false NOT NULL,
	handle text NULL,
	CONSTRAINT domain_contact_domain_id_type_id_is_private_privacy_local_key UNIQUE (source_domain_id, domain_contact_type_id, is_private, is_privacy_proxy, is_local_presence),
	CONSTRAINT domain_contact_pkey PRIMARY KEY (id),
	CONSTRAINT domain_contact_source_domain_id_fkey FOREIGN KEY (source_domain_id) REFERENCES dm_ascio."domain"(source_domain_id)
);

---- part that is not used 

CREATE TABLE dm_ascio.secdns_key_data(
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  flags       INT NOT NULL,
  protocol    INT NOT NULL DEFAULT 3,
  algorithm   INT NOT NULL,
  public_key  TEXT NOT NULL,
  CONSTRAINT flags_ok CHECK (
    -- equivalent to binary literal 0b011111110111111
    (flags & 65471) = 0
  ),
  CONSTRAINT algorithm_ok CHECK (
    algorithm IN (1,2,3,4,5,6,7,8,10,12,13,14,15,16,17,23,252,253,254)
  )
);

CREATE TABLE dm_ascio.secdns_ds_data(
	id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
 	key_tag      INT NOT NULL,
  	algorithm    INT NOT NULL,
  	digest_type  INT NOT NULL DEFAULT 1,
  	digest       TEXT NOT NULL,
  	key_data_id UUID REFERENCES dm_ascio.secdns_key_data ON DELETE CASCADE,
	CONSTRAINT algorithm_ok CHECK (
		algorithm IN (1,2,3,4,5,6,7,8,10,12,13,14,15,16,17,23,252,253,254)
	),
	CONSTRAINT digest_type_ok CHECK (
		digest_type IN (1,2,3,4,5,6)
	)
	);

CREATE TABLE dm_ascio.domain_secdns(
  id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id     UUID ,
  ds_data_id    UUID REFERENCES dm_ascio.secdns_ds_data ON DELETE CASCADE,
  key_data_id   UUID REFERENCES dm_ascio.secdns_key_data ON DELETE CASCADE,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  )
);