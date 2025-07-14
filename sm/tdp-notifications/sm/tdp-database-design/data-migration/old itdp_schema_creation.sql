--itdp is intermediate schema for data migration to TDP

CREATE SCHEMA IF NOT EXISTS itdp  AUTHORIZATION --tdpadm;  
--postgres;
tucows;

DO $$ BEGIN
    IF to_regtype('itdp.dm_status') IS NULL THEN
        CREATE TYPE itdp.dm_status AS (domain boolean, host boolean, public_contact boolean, private_contact boolean);
    END IF;
	IF to_regtype('itdp.dm_result') IS NULL THEN
        CREATE TYPE itdp.dm_result AS (extract int, dm_enom int,dm_enom_itdp_pk int, itdp int, error int, tdp int);
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
INSERT INTO itdp.lock_type (id,"name", descr) VALUES  
   ('3d0af86b-4d98-4ad1-9823-1e91108fe5ae','update', 'Requests to update the object MUST be rejected') ,
   ('ee070b2a-e75b-42b8-9469-5146db9b9221','delete','Requests to delete the object MUST be rejected'),
   ('8261baeb-89fc-4020-9e05-b17158f11d9c','transfer', 'Requests to transfer the object MUST be rejected'),
   ('3d97d496-4f1d-11e8-9bfd-02420a000396','hold','Signify that the object is on hold')
ON CONFLICT DO NOTHING ;

/*CREATE TABLE  IF NOT EXISTS itdp.rgp_status (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	epp_name text NOT NULL,
	descr text NOT NULL,
	CONSTRAINT rgp_status_name_key UNIQUE (name),
	CONSTRAINT rgp_status_pkey PRIMARY KEY (id)
);

INSERT INTO itdp.rgp_status(id,"name", epp_name,descr) VALUES
	('a065f49c-2885-4441-8561-0da40bd1e98b','add_grace_period','addPeriod','registry provides credit for deleted domain during this period for the cost of the registration'),
	('2e5b0938-b960-47ef-ad6f-1aa0558127e2','transfer_grace_period','transferPeriod','registry provides credit for deleted domain during this period for the cost of the transfer'),
	('bb30db25-10ac-4e3b-8b79-7baf6112a33a','autorenew_grace_period','autoRenewPeriod', 'registry provides credit for deleted domain during this period for the cost of the renewal'),
	('beb98ddd-559d-41fd-b574-b15c3213cd44', 'redemption_grace_period', 'redemptionPeriod', 'deleted domain might be restored during this period'),
	('cb233362-991c-4c9e-8170-0259fd8d9faf','pending_delete_period','pendingDelete','deleted domain not restored during redemptionPeriod')
ON CONFLICT DO NOTHING ;*/



   
CREATE TABLE IF NOT EXISTS  itdp.domain_status (
	id uuid NOT NULL DEFAULT gen_random_uuid(),
	"name" text NOT NULL,
	--TDP_name text NULL,
	descr text NOT NULL,
	CONSTRAINT domain_status_name_key UNIQUE (name),
	CONSTRAINT domain_status_pkey PRIMARY KEY (id)
);

INSERT INTO itdp.domain_status (id,name, descr) 
    VALUES 
        ('ddfa2bed-e332-40b9-9244-2440ffa2d555','Active', 'Domain is active'),
        ('24ac43cb-ff01-459a-8ed7-d1846b0404aa','Deleted', 'Domain is deleted in registry'), 
        ('ad4432b5-b99c-4385-ac33-477e6446216f','Expired', 'Domain has passed its expiration date'),
        ('b6131b33-1f4e-4169-93d7-6795009c3e7e','Extended RGP','Domain has entered its Redemption Grace Period (RGP), but will become part of our portfolio, or in some cases, could not be deleted normally'),
		('c0928677-ca0b-49fd-9df7-43446f9889cc','RGP','Domain name has passed  expiration grace period and is scheduled for deletion')
	
ON CONFLICT DO NOTHING ;
       
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


CREATE --UNLOGGED
TABLE  IF NOT EXISTS itdp.domain_lock (
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

-- Contact Types
INSERT INTO itdp.contact_type (id,name) 
    VALUES 
        ('061e7edf-1b00-454c-b10b-562e226c8500','individual'),
        ('99fdcfe1-b7fc-4e57-8c35-9887b2149056','organization') ON CONFLICT DO NOTHING ;


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

INSERT INTO itdp.country(name, alpha2, alpha3) VALUES
('Afghanistan',                                          'AF', 'AFG'),
('Åland Islands',                                        'AX', 'ALA'),
('Albania',                                              'AL', 'ALB'),
('Algeria',                                              'DZ', 'DZA'),
('American Samoa',                                       'AS', 'ASM'),
('Andorra',                                              'AD', 'AND'),
('Angola',                                               'AO', 'AGO'),
('Anguilla',                                             'AI', 'AIA'),
('Antarctica',                                           'AQ', 'ATA'),
('Antigua and Barbuda',                                  'AG', 'ATG'),
('Argentina',                                            'AR', 'ARG'),
('Armenia',                                              'AM', 'ARM'),
('Aruba',                                                'AW', 'ABW'),
('Australia',                                            'AU', 'AUS'),
('Austria',                                              'AT', 'AUT'),
('Azerbaijan',                                           'AZ', 'AZE'),
('Bahamas',                                              'BS', 'BHS'),
('Bahrain',                                              'BH', 'BHR'),
('Bangladesh',                                           'BD', 'BGD'),
('Barbados',                                             'BB', 'BRB'),
('Belarus',                                              'BY', 'BLR'),
('Belgium',                                              'BE', 'BEL'),
('Belize',                                               'BZ', 'BLZ'),
('Benin',                                                'BJ', 'BEN'),
('Bermuda',                                              'BM', 'BMU'),
('Bhutan',                                               'BT', 'BTN'),
('Bolivia (Plurinational State of)',                     'BO', 'BOL'),
('Bonaire, Sint Eustatius and Saba',                     'BQ', 'BES'),
('Bosnia and Herzegovina',                               'BA', 'BIH'),
('Botswana',                                             'BW', 'BWA'),
('Bouvet Island',                                        'BV', 'BVT'),
('Brazil',                                               'BR', 'BRA'),
('British Indian Ocean Territory',                       'IO', 'IOT'),
('Brunei Darussalam',                                    'BN', 'BRN'),
('Bulgaria',                                             'BG', 'BGR'),
('Burkina Faso',                                         'BF', 'BFA'),
('Burundi',                                              'BI', 'BDI'),
('Cambodia',                                             'KH', 'KHM'),
('Cameroon',                                             'CM', 'CMR'),
('Canada',                                               'CA', 'CAN'),
('Cabo Verde',                                           'CV', 'CPV'),
('Cayman Islands',                                       'KY', 'CYM'),
('Central African Republic',                             'CF', 'CAF'),
('Chad',                                                 'TD', 'TCD'),
('Chile',                                                'CL', 'CHL'),
('China',                                                'CN', 'CHN'),
('Christmas Island',                                     'CX', 'CXR'),
('Cocos (Keeling) Islands',                              'CC', 'CCK'),
('Colombia',                                             'CO', 'COL'),
('Comoros',                                              'KM', 'COM'),
('Congo',                                                'CG', 'COG'),
('Congo (Democratic Republic of the)',                   'CD', 'COD'),
('Cook Islands',                                         'CK', 'COK'),
('Costa Rica',                                           'CR', 'CRI'),
('Côte d''Ivoire',                                       'CI', 'CIV'),
('Croatia',                                              'HR', 'HRV'),
('Cuba',                                                 'CU', 'CUB'),
('Curaçao',                                              'CW', 'CUW'),
('Cyprus',                                               'CY', 'CYP'),
('Czech Republic',                                       'CZ', 'CZE'),
('Denmark',                                              'DK', 'DNK'),
('Djibouti',                                             'DJ', 'DJI'),
('Dominica',                                             'DM', 'DMA'),
('Dominican Republic',                                   'DO', 'DOM'),
('Ecuador',                                              'EC', 'ECU'),
('Egypt',                                                'EG', 'EGY'),
('El Salvador',                                          'SV', 'SLV'),
('Equatorial Guinea',                                    'GQ', 'GNQ'),
('Eritrea',                                              'ER', 'ERI'),
('Estonia',                                              'EE', 'EST'),
('Ethiopia',                                             'ET', 'ETH'),
('Falkland Islands (Malvinas)',                          'FK', 'FLK'),
('Faroe Islands',                                        'FO', 'FRO'),
('Fiji',                                                 'FJ', 'FJI'),
('Finland',                                              'FI', 'FIN'),
('France',                                               'FR', 'FRA'),
('French Guiana',                                        'GF', 'GUF'),
('French Polynesia',                                     'PF', 'PYF'),
('French Southern Territories',                          'TF', 'ATF'),
('Gabon',                                                'GA', 'GAB'),
('Gambia',                                               'GM', 'GMB'),
('Georgia',                                              'GE', 'GEO'),
('Germany',                                              'DE', 'DEU'),
('Ghana',                                                'GH', 'GHA'),
('Gibraltar',                                            'GI', 'GIB'),
('Greece',                                               'GR', 'GRC'),
('Greenland',                                            'GL', 'GRL'),
('Grenada',                                              'GD', 'GRD'),
('Guadeloupe',                                           'GP', 'GLP'),
('Guam',                                                 'GU', 'GUM'),
('Guatemala',                                            'GT', 'GTM'),
('Guernsey',                                             'GG', 'GGY'),
('Guinea',                                               'GN', 'GIN'),
('Guinea-Bissau',                                        'GW', 'GNB'),
('Guyana',                                               'GY', 'GUY'),
('Haiti',                                                'HT', 'HTI'),
('Heard Island and McDonald Islands',                    'HM', 'HMD'),
('Holy See',                                             'VA', 'VAT'),
('Honduras',                                             'HN', 'HND'),
('Hong Kong',                                            'HK', 'HKG'),
('Hungary',                                              'HU', 'HUN'),
('Iceland',                                              'IS', 'ISL'),
('India',                                                'IN', 'IND'),
('Indonesia',                                            'ID', 'IDN'),
('Iran (Islamic Republic of)',                           'IR', 'IRN'),
('Iraq',                                                 'IQ', 'IRQ'),
('Ireland',                                              'IE', 'IRL'),
('Isle of Man',                                          'IM', 'IMN'),
('Israel',                                               'IL', 'ISR'),
('Italy',                                                'IT', 'ITA'),
('Jamaica',                                              'JM', 'JAM'),
('Japan',                                                'JP', 'JPN'),
('Jersey',                                               'JE', 'JEY'),
('Jordan',                                               'JO', 'JOR'),
('Kazakhstan',                                           'KZ', 'KAZ'),
('Kenya',                                                'KE', 'KEN'),
('Kiribati',                                             'KI', 'KIR'),
('Korea (Democratic People''s Republic of)',             'KP', 'PRK'),
('Korea (Republic of)',                                  'KR', 'KOR'),
('Kuwait',                                               'KW', 'KWT'),
('Kyrgyzstan',                                           'KG', 'KGZ'),
('Lao People''s Democratic Republic',                    'LA', 'LAO'),
('Latvia',                                               'LV', 'LVA'),
('Lebanon',                                              'LB', 'LBN'),
('Lesotho',                                              'LS', 'LSO'),
('Liberia',                                              'LR', 'LBR'),
('Libya',                                                'LY', 'LBY'),
('Liechtenstein',                                        'LI', 'LIE'),
('Lithuania',                                            'LT', 'LTU'),
('Luxembourg',                                           'LU', 'LUX'),
('Macao',                                                'MO', 'MAC'),
('Macedonia (the former Yugoslav Republic of)',          'MK', 'MKD'),
('Madagascar',                                           'MG', 'MDG'),
('Malawi',                                               'MW', 'MWI'),
('Malaysia',                                             'MY', 'MYS'),
('Maldives',                                             'MV', 'MDV'),
('Mali',                                                 'ML', 'MLI'),
('Malta',                                                'MT', 'MLT'),
('Marshall Islands',                                     'MH', 'MHL'),
('Martinique',                                           'MQ', 'MTQ'),
('Mauritania',                                           'MR', 'MRT'),
('Mauritius',                                            'MU', 'MUS'),
('Mayotte',                                              'YT', 'MYT'),
('Mexico',                                               'MX', 'MEX'),
('Micronesia (Federated States of)',                     'FM', 'FSM'),
('Moldova (Republic of)',                                'MD', 'MDA'),
('Monaco',                                               'MC', 'MCO'),
('Mongolia',                                             'MN', 'MNG'),
('Montenegro',                                           'ME', 'MNE'),
('Montserrat',                                           'MS', 'MSR'),
('Morocco',                                              'MA', 'MAR'),
('Mozambique',                                           'MZ', 'MOZ'),
('Myanmar',                                              'MM', 'MMR'),
('Namibia',                                              'NA', 'NAM'),
('Nauru',                                                'NR', 'NRU'),
('Nepal',                                                'NP', 'NPL'),
('Netherlands',                                          'NL', 'NLD'),
('New Caledonia',                                        'NC', 'NCL'),
('New Zealand',                                          'NZ', 'NZL'),
('Nicaragua',                                            'NI', 'NIC'),
('Niger',                                                'NE', 'NER'),
('Nigeria',                                              'NG', 'NGA'),
('Niue',                                                 'NU', 'NIU'),
('Norfolk Island',                                       'NF', 'NFK'),
('Northern Mariana Islands',                             'MP', 'MNP'),
('Norway',                                               'NO', 'NOR'),
('Oman',                                                 'OM', 'OMN'),
('Pakistan',                                             'PK', 'PAK'),
('Palau',                                                'PW', 'PLW'),
('Palestine, State of',                                  'PS', 'PSE'),
('Panama',                                               'PA', 'PAN'),
('Papua New Guinea',                                     'PG', 'PNG'),
('Paraguay',                                             'PY', 'PRY'),
('Peru',                                                 'PE', 'PER'),
('Philippines',                                          'PH', 'PHL'),
('Pitcairn',                                             'PN', 'PCN'),
('Poland',                                               'PL', 'POL'),
('Portugal',                                             'PT', 'PRT'),
('Puerto Rico',                                          'PR', 'PRI'),
('Qatar',                                                'QA', 'QAT'),
('Réunion',                                              'RE', 'REU'),
('Romania',                                              'RO', 'ROU'),
('Russian Federation',                                   'RU', 'RUS'),
('Rwanda',                                               'RW', 'RWA'),
('Saint Barthélemy',                                     'BL', 'BLM'),
('Saint Helena, Ascension and Tristan da Cunha',         'SH', 'SHN'),
('Saint Kitts and Nevis',                                'KN', 'KNA'),
('Saint Lucia',                                          'LC', 'LCA'),
('Saint Martin (French part)',                           'MF', 'MAF'),
('Saint Pierre and Miquelon',                            'PM', 'SPM'),
('Saint Vincent and the Grenadines',                     'VC', 'VCT'),
('Samoa',                                                'WS', 'WSM'),
('San Marino',                                           'SM', 'SMR'),
('Sao Tome and Principe',                                'ST', 'STP'),
('Saudi Arabia',                                         'SA', 'SAU'),
('Senegal',                                              'SN', 'SEN'),
('Serbia',                                               'RS', 'SRB'),
('Seychelles',                                           'SC', 'SYC'),
('Sierra Leone',                                         'SL', 'SLE'),
('Singapore',                                            'SG', 'SGP'),
('Sint Maarten (Dutch part)',                            'SX', 'SXM'),
('Slovakia',                                             'SK', 'SVK'),
('Slovenia',                                             'SI', 'SVN'),
('Solomon Islands',                                      'SB', 'SLB'),
('Somalia',                                              'SO', 'SOM'),
('South Africa',                                         'ZA', 'ZAF'),
('South Georgia and the South Sandwich Islands',         'GS', 'SGS'),
('South Sudan',                                          'SS', 'SSD'),
('Spain',                                                'ES', 'ESP'),
('Sri Lanka',                                            'LK', 'LKA'),
('Sudan',                                                'SD', 'SDN'),
('Suriname',                                             'SR', 'SUR'),
('Svalbard and Jan Mayen',                               'SJ', 'SJM'),
('Swaziland',                                            'SZ', 'SWZ'),
('Sweden',                                               'SE', 'SWE'),
('Switzerland',                                          'CH', 'CHE'),
('Syrian Arab Republic',                                 'SY', 'SYR'),
('Taiwan, Province of China',                            'TW', 'TWN'),
('Tajikistan',                                           'TJ', 'TJK'),
('Tanzania, United Republic of',                         'TZ', 'TZA'),
('Thailand',                                             'TH', 'THA'),
('Timor-Leste',                                          'TL', 'TLS'),
('Togo',                                                 'TG', 'TGO'),
('Tokelau',                                              'TK', 'TKL'),
('Tonga',                                                'TO', 'TON'),
('Trinidad and Tobago',                                  'TT', 'TTO'),
('Tunisia',                                              'TN', 'TUN'),
('Turkey',                                               'TR', 'TUR'),
('Turkmenistan',                                         'TM', 'TKM'),
('Turks and Caicos Islands',                             'TC', 'TCA'),
('Tuvalu',                                               'TV', 'TUV'),
('Uganda',                                               'UG', 'UGA'),
('Ukraine',                                              'UA', 'UKR'),
('United Arab Emirates',                                 'AE', 'ARE'),
('United Kingdom of Great Britain and Northern Ireland', 'GB', 'GBR'),
('United States of America',                             'US', 'USA'),
('United States Minor Outlying Islands',                 'UM', 'UMI'),
('Uruguay',                                              'UY', 'URY'),
('Uzbekistan',                                           'UZ', 'UZB'),
('Vanuatu',                                              'VU', 'VUT'),
('Venezuela (Bolivarian Republic of)',                   'VE', 'VEN'),
('Viet Nam',                                             'VN', 'VNM'),
('Virgin Islands (British)',                             'VG', 'VGB'),
('Virgin Islands (U.S.)',                                'VI', 'VIR'),
('Wallis and Futuna',                                    'WF', 'WLF'),
('Western Sahara',                                       'EH', 'ESH'),
('Yemen',                                                'YE', 'YEM'),
('Zambia',                                               'ZM', 'ZMB'),
('Zimbabwe',                                             'ZW', 'ZWE')
ON CONFLICT DO NOTHING ;


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
-- TODO: Populate table 'language'.
INSERT INTO itdp.language(name, alpha2, alpha3t, alpha3b) VALUES
	('English', 'en', 'eng', 'eng'),
	('German',  'de', 'deu', 'ger')
ON CONFLICT DO NOTHING ;

CREATE --UNLOGGED 
TABLE  IF NOT EXISTS  itdp.contact (
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
	fax text NULL,
	country text NOT NULL,
	"language" text NULL,	
	TDP_contact_country_issue boolean default False  NULL,  
	--TDP_contact_city_issue boolean default False  NULL,  
	TDP_data_source varchar(15) NULL,	
	placeholder boolean default false, -- Public contact data was replaced on placeholders data.
	domain_contact_type_name varchar(20) NULL,
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
	fax text NULL,
	country text NULL,
	"language" text NULL,	
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

INSERT INTO itdp.domain_contact_type (id,name) 
    VALUES 
        ('5a869dcd-0435-430a-9dfa-2ab286da3ab8','registrant'),
        ('7b9d05e4-88a1-42aa-a050-5d30f4b833e2','admin'),
        ('a95636da-8399-4867-9797-f8452269003b','tech'),
        ('14036972-309f-443e-8c16-5115356bb68d','billing')
 ON CONFLICT DO NOTHING ;       


CREATE TABLE IF NOT EXISTS itdp.tld (
	id uuid DEFAULT gen_random_uuid() NOT NULL,	
	phase varchar NOT NULL, --1.1, 1.2, 1.3
	dm_source varchar(15) NOT NULL,
	TLD_name varchar(15) NOT NULL,
	is_thin boolean default false NOT NULL,  -- thin - true/thick - false - should be populate from source dm 
	min_nameservers int default 0 NOT NULL,
	tenant_customer_id uuid NOT NULL, -- from tdpdb.public.v_accreditation_tld
    accreditation_tld_id uuid NOT NULL, -- from tdpdb.public.v_accreditation_tld
	migration_status varchar(20) NULL , -- done,NULL
	result_domain itdp.dm_result null,
	result_contact itdp.dm_result null,
	result_host itdp.dm_result null,
	updated_date timestamptz NULL,
	Is_Active boolean default TRUE,	
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
	

	
	

    
