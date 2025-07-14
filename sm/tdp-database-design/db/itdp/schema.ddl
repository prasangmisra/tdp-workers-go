--itdp is intermediate schema for data migration to TDP
CREATE SCHEMA IF NOT EXISTS itdp;  

DO $$ BEGIN
    IF to_regtype('itdp.dm_status') IS NULL THEN
        CREATE TYPE itdp.dm_status AS (domain boolean, host boolean, public_contact boolean, private_contact boolean);
    END IF;
	IF to_regtype('itdp.dm_result') IS NULL THEN
        CREATE TYPE itdp.dm_result AS (extract int, dm_enom int,dm_enom_itdp_pk int, itdp int, error int, tdp int);
    END IF;
	IF to_regtype('itdp.dm_result_add') IS NULL THEN
        CREATE TYPE itdp.dm_result_add AS (status varchar(20), date timestamptz, result itdp.dm_result );
    END IF;
END $$;
	
CREATE TABLE IF NOT EXISTS itdp.SSIS_errorlog (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	machineName text NULL,
	packageName text NULL,
	taskName text NULL,
	ErrorCode INT NULL,
	ErrorDescription text NULL,
	Dated timestamptz NULL);

CREATE TABLE IF NOT EXISTS itdp.lock_type (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	descr text NOT NULL,
	CONSTRAINT lock_type_name_key UNIQUE (name),
	CONSTRAINT lock_type_pkey PRIMARY KEY (id)
);

   
CREATE TABLE IF NOT EXISTS  itdp.domain_status (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	"name" text NOT NULL,
	--TDP_name text NULL,
	descr text NOT NULL,
	CONSTRAINT domain_status_name_key UNIQUE (name),
	CONSTRAINT domain_status_pkey PRIMARY KEY (id)
);

       
CREATE TABLE IF NOT EXISTS  itdp."domain" (
    tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
    source_domain_id int NOT NULL,    
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	tenant_customer_id uuid  NULL,
	accreditation_tld_id uuid  NULL,
	"name" public.fqdn  NOT NULL,
	auth_info text NULL,
	roid text NULL,
	ry_created_date timestamptz  NULL,
	ry_expiry_date timestamptz  NULL,
	ry_updated_date timestamptz NULL,
	ry_transfered_date timestamptz NULL,   -- 'transfer in' domain
	deleted_date timestamptz NULL,
	expiry_date timestamptz NOT NULL,
	status_id uuid NOT NULL,
	auto_renew bool NOT NULL DEFAULT true,
	registration_period int4 DEFAULT 1 NOT NULL,
    dm_status itdp.dm_status NULL,		
	uname text NULL,
	language text NULL,
	secdns_max_sig_life int4 NULL,
	TDP_min_namesrvers_issue boolean default False  NULL,
	CONSTRAINT domain_pkey PRIMARY KEY (dm_source,tld,id)
	-- will be created on partition CONSTRAINT domain_name_key UNIQUE (dm_source,tld,name),	
	-- will be created on partition CONSTRAINT domain_status_id_fkey FOREIGN KEY (status_id) REFERENCES itdp.domain_status(id)
) partition by list(dm_source);
-- will be created on partition CREATE INDEX  IF NOT EXISTS domain_source_domain_id_idx ON itdp.domain USING btree (source_domain_id);



CREATE TABLE IF NOT EXISTS  itdp.domain_error_records (
    tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
    source_domain_id int  NULL,    
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	tenant_customer_id uuid  NULL,
	accreditation_tld_id uuid  NULL,
	"name" text  NULL,
	auth_info text NULL,
	roid text NULL,
	ry_created_date timestamptz  NULL,
	ry_expiry_date timestamptz  NULL,
	ry_updated_date timestamptz NULL,
	ry_transfered_date timestamptz NULL,
	deleted_date timestamptz NULL,
	expiry_date timestamptz  NULL,
	status_id uuid  NULL,
	auto_renew bool  NULL DEFAULT true,
	registration_period int4 DEFAULT 1 NOT NULL,
	errorcode int Null,
	errorcolumn int NULL,
	errordescription text NULL
);
--CREATE INDEX  IF NOT EXISTS domain_error_tld_idx ON itdp.domain_error_records USING btree (tld);


CREATE TABLE  IF NOT EXISTS itdp.domain_lock (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
	domain_id uuid NOT NULL,
	type_id uuid NOT NULL,
	is_internal bool DEFAULT false NOT NULL,
	created_date timestamptz DEFAULT now() NULL,
	expiry_date timestamptz NULL,
	CONSTRAINT domain_lock_check CHECK (((expiry_date IS NULL) OR ((expiry_date IS NOT NULL) AND is_internal))),
	CONSTRAINT domain_lock_domain_id_type_id_is_internal_key UNIQUE (domain_id, type_id, is_internal),
	CONSTRAINT domain_lock_pkey PRIMARY KEY (id),
	CONSTRAINT domain_lock_domain_id_fkey FOREIGN KEY (dm_source, tld, domain_id) REFERENCES itdp."domain"(dm_source, tld, id),
	CONSTRAINT domain_lock_type_id_fkey FOREIGN KEY (type_id) REFERENCES itdp.lock_type(id)
);

-------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS  itdp.host (
    tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
    source_host_id int  NULL,
	source_domain_id int  NULL,  
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	itdp_domain_id  uuid NOT NULL ,
	tenant_customer_id uuid  NULL,
	"name" text NOT NULL,
	--domain_id uuid  NULL,
	host_id_unique_name uuid NULL , --( only for phase1)
	host_id_unique_name_tdp uuid NULL , -- check if in TDP alredy exists host name ( only for phase1)
	CONSTRAINT host_pkey PRIMARY KEY (dm_source,tld,id)	
	) partition by list(dm_source);
-- will be created on partition CREATE INDEX  IF NOT EXISTS host_source_host_id_idx ON itdp.host USING btree (source_host_id);
-- will be created on partition CREATE INDEX  IF NOT EXISTS host_name_idx ON itdp.host USING btree (name);
-- will be created on partition CREATE INDEX  IF NOT EXISTS host_itdp_domain_id_idx ON itdp.host USING btree (itdp_domain_id) ;


CREATE TABLE IF NOT EXISTS  itdp.host_error_records (
    tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
    source_host_id int  NULL,
	source_domain_id int  NULL,  
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	itdp_domain_id  uuid  NULL,
	tenant_customer_id uuid  NULL,
	"name" text  NULL,
	--domain_id uuid NULL,
	errorcode int Null,
	errorcolumn int NULL,
	ErrorDescription text NULL);

----------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS  itdp.contact_type (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	"name" text NOT NULL,
	descr text NULL,
	CONSTRAINT contact_type_name_key UNIQUE (name),
	CONSTRAINT contact_type_pkey PRIMARY KEY (id)
);


CREATE TABLE IF NOT EXISTS  itdp.country (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	"name" text NOT NULL,
	alpha2 text NOT NULL,
	alpha3 text NOT NULL,
	calling_code text NULL,
	CONSTRAINT country_alpha2_check CHECK ((length(alpha2) = 2)),
	CONSTRAINT country_alpha2_key UNIQUE (alpha2),
	CONSTRAINT country_alpha3_check CHECK ((length(alpha3) = 3)),
	CONSTRAINT country_alpha3_key UNIQUE (alpha3),
	CONSTRAINT country_name_key UNIQUE (name),
	CONSTRAINT country_pkey PRIMARY KEY (id)
);


CREATE TABLE IF NOT EXISTS  itdp."language" (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	"name" text NOT NULL,
	alpha2 text NOT NULL,
	alpha3t text NOT NULL,
	alpha3b text NOT NULL,
	CONSTRAINT language_alpha2_check CHECK ((length(alpha2) = 2)),
	CONSTRAINT language_alpha2_key UNIQUE (alpha2),
	CONSTRAINT language_alpha3b_check CHECK ((length(alpha3b) = 3)),
	CONSTRAINT language_alpha3b_key UNIQUE (alpha3b),
	CONSTRAINT language_alpha3t_check CHECK ((length(alpha3t) = 3)),
	CONSTRAINT language_alpha3t_key UNIQUE (alpha3t),
	CONSTRAINT language_name_key UNIQUE (name),
	CONSTRAINT language_pkey PRIMARY KEY (id)
);


CREATE TABLE  IF NOT EXISTS  itdp.contact (
    tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
	source_contact_id uuid NOT NULL,	
	source_domain_id int  NULL,  
	id uuid NOT NULL DEFAULT gen_random_uuid(),	
	itdp_domain_id  uuid NOT NULL ,	
	type_id uuid NOT NULL,
	title text NULL,
	org_reg text NULL,
	org_vat text NULL,
	org_duns text NULL,
	tenant_customer_id uuid NULL,
	email public."mbox" NULL,
	phone text NULL,
	phone_ext text NULL,
	fax text NULL,
	fax_ext text NULL,
	country text NOT NULL,
	"language" text NULL,	
	TDP_contact_country_issue boolean default False  NULL,  
	--TDP_contact_city_issue boolean default False  NULL,  
	TDP_data_source varchar(15) NULL,	
	placeholder boolean default false, -- Public contact data was replaced on placeholders data.
	domain_contact_type_name varchar(20) NULL,
	is_private boolean default false,
	handle text NULL,
	CONSTRAINT contact_pkey PRIMARY KEY (dm_source,tld,id) 
	-- will create on partition CONSTRAINT contact_country_fkey FOREIGN KEY (country) REFERENCES itdp.country(alpha2),
	-- will create on partition CONSTRAINT contact_language_fkey FOREIGN KEY ("language") REFERENCES itdp."language"(alpha2),
	-- will create on partitionCONSTRAINT contact_type_id_fkey FOREIGN KEY (type_id) REFERENCES itdp.contact_type(id) 
) partition by list(dm_source);
 -- will create on partition CREATE INDEX  IF NOT EXISTS contact_source_contact_id_idx ON itdp.contact USING btree (source_contact_id);  


CREATE TABLE  IF NOT EXISTS  itdp.contact_error_records (
    tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
	source_contact_id uuid NOT NULL,
	source_domain_id int  NULL,  
	id uuid NOT NULL DEFAULT gen_random_uuid(),	
	itdp_domain_id  uuid  NULL ,		
	type_id uuid NOT NULL,
	title text NULL,
	org_reg text NULL,
	org_vat text NULL,
	org_duns text NULL,
	tenant_customer_id uuid NULL,
	email text NULL,
	phone text NULL,
	phone_ext text NULL,
	fax text NULL,
	fax_ext text NULL,
	country text NULL,
	"language" text NULL,	
	is_private boolean default false,
	TDP_contact_country_issue boolean default False  NULL,  	 
	TDP_data_source varchar(15) NULL,	
	errorcode int Null,
	errorcolumn int NULL,
	errordescription text NULL);
CREATE INDEX  IF NOT EXISTS contact_error_tld_idx ON itdp.contact_error_records USING btree (tld);


CREATE  TABLE IF NOT EXISTS  itdp.contact_postal (
	tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	source_contact_id uuid NOT NULL,
	contact_id uuid  NULL,
	is_international bool NOT NULL,
	first_name text NULL,
	last_name text NULL,
	org_name text NULL,
	address1 text NOT NULL,
	address2 text NULL,
	address3 text NULL,
	city text NOT NULL,
	postal_code text NULL,
	state text NULL,
	CONSTRAINT contact_postal_pkey PRIMARY KEY (dm_source,tld,id)
	-- will create on partition CONSTRAINT contact_postal_contact_id_fkey FOREIGN KEY (dm_source,tld,contact_id) REFERENCES itdp.contact(dm_source,tld,id)-- DEFERRABLE INITIALLY DEFERRED
    -- will create on partition CONSTRAINT contact_postal_check CHECK (((NOT is_international) OR (is_null_or_ascii(first_name) AND is_null_or_ascii(last_name)
	/*AND is_null_or_ascii(org_name) AND is_null_or_ascii(address1) AND is_null_or_ascii(address2) AND is_null_or_ascii(address3)
	AND is_null_or_ascii(city) AND is_null_or_ascii(postal_code) AND is_null_or_ascii(state)))) ,*/
	-- will create on partition CONSTRAINT contact_postal_contact_id_is_international_key UNIQUE (dm_source,tld,contact_id, is_international),-- DEFERRABLE INITIALLY DEFERRED,
) partition by list(dm_source);


CREATE TABLE IF NOT EXISTS  itdp.contact_postal_error_records (
	tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	contact_id uuid  NULL,
	source_contact_id uuid NOT NULL,
	is_international bool NOT NULL,
	first_name text NULL,
	last_name text NULL,
	org_name text NULL,
	address1 text NOT NULL,
	address2 text NULL,
	address3 text NULL,
	city text  NULL,
	postal_code text NULL,
	state text NULL,	
	errorcode int Null,
	errorcolumn int NULL,
	errordescription text NULL);
CREATE INDEX  IF NOT EXISTS contact_postal_error_tld_idx ON itdp.contact_postal_error_records USING btree (tld);
	


CREATE TABLE IF NOT EXISTS  itdp.domain_contact_type (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	"name" text NOT NULL,
	descr text NULL,
	CONSTRAINT domain_contact_type_name_key UNIQUE (name),
	CONSTRAINT domain_contact_type_pkey PRIMARY KEY (id)
);


CREATE TABLE IF NOT EXISTS itdp.tld (
	id uuid DEFAULT gen_random_uuid() NOT NULL,	
	phase varchar NOT NULL, --1.1, 1.2, 1.3
	dm_source varchar(15) NOT NULL,
	TLD_name varchar(15) NOT NULL,
	is_thin boolean default false NOT NULL,  -- thin - true/thick - false - should be populate from source dm 	
	tenant_customer_id uuid NOT NULL, -- from tdpdb.public.v_accreditation_tld
    accreditation_tld_id uuid NOT NULL, -- from tdpdb.public.v_accreditation_tld
	migration_status varchar(20) NULL , -- done,NULL
	result_domain itdp.dm_result null,
	result_contact itdp.dm_result null,
	result_host itdp.dm_result null,
	updated_date timestamptz NULL,
	Is_Active boolean default TRUE,	
	private_contact itdp.dm_result_add NULL,
	contact_attribute itdp.dm_result_add NULL,
	CONSTRAINT tld_PK primary key  (id),
   	CONSTRAINT accreditation_tld_id_fkey FOREIGN KEY (accreditation_tld_id) REFERENCES public.accreditation_tld(id),
	CONSTRAINT tenant_customer_id_fkey FOREIGN KEY (tenant_customer_id) REFERENCES public.tenant_customer(id),
	CONSTRAINT tld_name__dm_source UNIQUE (dm_source, TLD_name)
    );


	CREATE TABLE IF NOT EXISTS itdp.dm_log (
	Id int NOT NULL,-- GENERATED BY DEFAULT AS IDENTITY ,	
	phase varchar NOT NULL, --1.1, 1.2, 1.3
	dm_source varchar(15) NOT NULL,
	TLD varchar(15) NOT NULL,	
	start_date timestamptz NULL,	
	end_date_extract timestamptz  NULL,
	end_date_itdp_transfer timestamptz  NULL,
	end_date_tdp_transfer timestamptz  NULL,
	end_date timestamptz  NULL,
	status varchar(100) NULL,	
	result_domain itdp.dm_result null,
	result_contact itdp.dm_result null,
	result_host itdp.dm_result null,
	migration_status varchar(20) NULL , -- done,NULL, Repeat TDP
	CONSTRAINT dm_log_PK primary key  (id)
	);
	CREATE INDEX  IF NOT EXISTS dm_log_tld_idx ON itdp.dm_log USING btree (tld);


	CREATE TABLE IF NOT EXISTS  itdp.host_addr (
	tld varchar(15) NOT NULL,
	dm_source varchar(15) NOT NULL,
	source_host_id int NULL,
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	itdp_host_id uuid NOT NULL,
	address INET NULL,
	CONSTRAINT host_addr_pkey PRIMARY KEY (dm_source,tld,id)
) partition by list(dm_source);
	

	
	

    
