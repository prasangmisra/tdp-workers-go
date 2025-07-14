INSERT INTO attr_category(name,descr)
    VALUES
        ('tld','TLD Settings'),
        ('provider','Provider Settings'),
        ('accreditation','Accreditation Settings'),
        ('hosting', 'Hosting general settings');


INSERT INTO attr_category(name,descr,parent_id)
    VALUES
      ('contact','Contact',(SELECT id FROM attr_category WHERE name='tld')),
      ('dns','Domain Name System',(SELECT id FROM attr_category WHERE name='tld')),
      ('eligibility','Eligibility',(SELECT id FROM attr_category WHERE name='tld')),
      ('lifecycle','Domain Lifecycle',(SELECT id FROM attr_category WHERE name='tld')),
      ('order','Order Information',(SELECT id FROM attr_category WHERE name='tld')),
      ('period','Registration Period',(SELECT id FROM attr_category WHERE name='tld')),
      ('premium','Premium Domains',(SELECT id FROM attr_category WHERE name='tld')),
      ('general','TLD General Setting',(SELECT id FROM attr_category WHERE name='tld')),
      ('whois','Whois Information',(SELECT id FROM attr_category WHERE name='tld')),
      ('finance', 'Cost Price Billing Currency information',(SELECT id FROM attr_category WHERE name='tld'));


INSERT INTO attr_value_type(name,data_type)
    VALUES
      ('INTEGER','INTEGER'),
      ('TEXT','TEXT'),
      ('INTEGER_RANGE','INT4RANGE'),
      ('INTERVAL','INTERVAL'),
      ('BOOLEAN','BOOLEAN'),
      ('TEXT_LIST','TEXT[]'),
      ('INTEGER_LIST','INT[]'),
      ('DATERANGE','DATERANGE'),
      ('TSTZRANGE','TSTZRANGE'),
      ('REGEX','REGEX'),
      ('PERCENTAGE','PERCENTAGE');


INSERT INTO attr_key(
  name,
  category_id,
  descr,
  value_type_id,
  default_value,
  allow_null)
VALUES
-- contact category
(
  'is_contact_update_supported',
  tc_id_from_name('attr_category', 'contact'),
  'Registry supports updating contact via update command',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  TRUE
),
(
  'optional_contact_types',
  tc_id_from_name('attr_category', 'contact'),
  'Optional contact types by registry',
  tc_id_from_name('attr_value_type', 'TEXT_LIST'),
  '{}'::TEXT,
  TRUE
),
(
  'registrant_contact_update_restricted_fields',
  tc_id_from_name('attr_category', 'contact'),
  'List of registrant fields restricted in contact update',
  tc_id_from_name('attr_value_type', 'TEXT_LIST'),
  ARRAY['first_name','last_name','org_name','email']::TEXT,
  TRUE
),
(
  'required_contact_types',
  tc_id_from_name('attr_category', 'contact'),
  'Required contact types by registry',
  tc_id_from_name('attr_value_type', 'TEXT_LIST'),
  ARRAY['registrant']::TEXT,
  TRUE
),

-- dns category
(
  'allowed_nameserver_count',
  tc_id_from_name('attr_category', 'dns'),
  'Range of minimum and maximum required nameservers by registry',
  tc_id_from_name('attr_value_type', 'INTEGER_RANGE'),
  '[2, 13]'::TEXT,
  FALSE
),
(
  'ipv6_support',
  tc_id_from_name('attr_category', 'dns'),
  'Registry supports IPv6 for Nameservers',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  FALSE::TEXT,
  FALSE
),
(
  'secdns_record_count',
  tc_id_from_name('attr_category', 'dns'),
  'Range of minimum and maximum secdns record count',
  tc_id_from_name('attr_value_type', 'INTEGER_RANGE'),
  '[0, 0]'::TEXT,
  FALSE
),

-- finance category
(
  'currency',
  tc_id_from_name('attr_category', 'finance'),
  'Accreditation currency: registry-tenant-tld',
  tc_id_from_name('attr_value_type', 'TEXT'),
  'USD'::TEXT,
  FALSE
),

-- hosting category
(
  'dns_check_interval',
  tc_id_from_name('attr_category', 'hosting'),
  'Interval in units for checking DNS setup',
  tc_id_from_name('attr_value_type', 'INTERVAL'),
  '1 hour'::TEXT,
  FALSE
),
(
  'dns_check_max_retries',
  tc_id_from_name('attr_category', 'hosting'),
  'Maximum number of retries for checking DNS setup',
  tc_id_from_name('attr_value_type', 'INTERVAL'),
  '72'::INT,
  FALSE
),

-- lifecycle category
(
  'add_grace_period',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry add grace period length in hours',
  tc_id_from_name('attr_value_type', 'INTEGER'),
  120::TEXT,
  FALSE
),
(
  'allowed_registration_periods',
  tc_id_from_name('attr_category', 'lifecycle'),
  'List of allowed registration periods',
  tc_id_from_name('attr_value_type', 'INTEGER_LIST'),
  '{1,2,3,4,5,6,7,8,9,10}'::TEXT,
  FALSE
),
(
  'allowed_renewal_periods',
  tc_id_from_name('attr_category', 'lifecycle'),
  'List of allowed renewal periods',
  tc_id_from_name('attr_value_type', 'INTEGER_LIST'),
  '{1,2,3,4,5,6,7,8,9,10}'::TEXT,
  FALSE
),
(
  'allowed_transfer_periods',
  tc_id_from_name('attr_category', 'lifecycle'),
  'List of allowed transfer periods',
  tc_id_from_name('attr_value_type', 'INTEGER_LIST'),
  '{1}'::TEXT,
  FALSE
),
(
  'authcode_acceptance_criteria',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Regex pattern to verify auth info',
  tc_id_from_name('attr_value_type', 'TEXT'),
  '^.{1,255}$'::TEXT,
  FALSE
),
(
  'claims_period',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Start and end date of claims period',
  tc_id_from_name('attr_value_type', 'TSTZRANGE'),
  NULL::TEXT,
  FALSE
),
(
  'domain_length',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Range of minimum and maximum domain length',
  tc_id_from_name('attr_value_type', 'INTEGER_RANGE'),
  '[3, 63]'::TEXT,
  TRUE
),
(
  'fee_check_allowed',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry supports fee check',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'is_thin_registry',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Thin Registry',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  FALSE::TEXT,
  FALSE
),
(
  'is_tld_active',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Is TLD active',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'max_lifetime',
  tc_id_from_name('attr_category', 'lifecycle'),
  'max lifetime of a domain in years',
  tc_id_from_name('attr_value_type', 'INTEGER'),
  10::TEXT,
  FALSE
),
(
  'pending_delete_period',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry pending grace delete length in hours',
  tc_id_from_name('attr_value_type', 'INTEGER'),
  120::TEXT,
  FALSE
),
(
  'redemption_grace_period',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry redemption grace period length in hours',
  tc_id_from_name('attr_value_type', 'INTEGER'),
  715::TEXT,
  FALSE
),
(
  'renew_is_premium',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry renew is premium',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'redeem_is_premium',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry redeem is premium',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'transfer_is_premium',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry transfer is premium',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'transfer_grace_period',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry transfer grace period length in hours',
  tc_id_from_name('attr_value_type', 'INTEGER'),
  120::TEXT,
  FALSE
),
(
  'autorenew_grace_period',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry auto-renew grace period length in hours',
  tc_id_from_name('attr_value_type', 'INTEGER'),
  1080::TEXT,
  FALSE
),
(
  'premium_domain_enabled',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Is premium domain enabled',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  FALSE::TEXT,
  FALSE
),
(
  'transfer_server_auto_approve_supported',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry supports auto approve transfer',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'is_redeem_report_required',
  tc_id_from_name('attr_category', 'lifecycle'),
  'Registry requires redemption report for redemption commands',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
-- order category
(
  'authcode_mandatory_for_orders',
  tc_id_from_name('attr_category', 'order'),
  'List of order types which require authcode',
  tc_id_from_name('attr_value_type', 'TEXT_LIST'),
  '{}'::TEXT,
  FALSE
),
(
  'authcode_supported_for_orders',
  tc_id_from_name('attr_category', 'order'),
  'List of order types which support authcode',
  tc_id_from_name('attr_value_type', 'TEXT_LIST'),
  ARRAY['registration','transfer_in','update','owner_change']::TEXT,
  FALSE
),
(
  'host_delete_rename_allowed',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports renaming host during delete',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  FALSE::TEXT,
  FALSE
),
(
  'host_delete_rename_domain',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports renaming host during delete with domain',
  tc_id_from_name('attr_value_type', 'TEXT'),
  ''::TEXT,
  FALSE
),
(
  'host_object_supported',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports host objects',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'host_ip_required_non_auth',
  tc_id_from_name('attr_category', 'order'),
  'Registry requires host IP addresses',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  FALSE::TEXT,
  FALSE
),
(
  'is_add_update_lock_with_domain_content_supported',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports updating the domain and adding the domain update lock with a single command.',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  TRUE
),
(
  'is_delete_allowed',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports domain delete',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'is_redeem_allowed',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports domain redemption',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'is_registration_allowed',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports domain registration',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'is_rem_update_lock_with_domain_content_supported',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports updating the domain and removing the domain update lock with a single command.',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  FALSE::TEXT,
  TRUE
),
(
  'is_transfer_allowed',
  tc_id_from_name('attr_category', 'order'),
  'Registry supports domain transfer',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  TRUE::TEXT,
  FALSE
),
(
  'outgoing_transfer_standard_response',
  tc_id_from_name('attr_category', 'order'),
  'NOT IN USE: Standard response for outgoing transfers',
  tc_id_from_name('attr_value_type', 'TEXT'),
  NULL::TEXT,
  TRUE
),
(
  'secdns_supported',
  tc_id_from_name('attr_category', 'order'),
  'List of supported secdns types',
  tc_id_from_name('attr_value_type', 'TEXT_LIST'),
  '{}'::TEXT,
  FALSE
),
(
  'supported_idn_lang_tags',
  tc_id_from_name('attr_category', 'order'),
  'List of supported IDN language tags',
  tc_id_from_name('attr_value_type', 'TEXT_LIST'),
  '{}'::TEXT,
  FALSE
),
(
    'rdp_enabled',
    tc_id_from_name('attr_category', 'order'),
    'RDP filters enabled',
    tc_id_from_name('attr_value_type', 'BOOLEAN'),
    FALSE::TEXT,
    FALSE
),
-- premium category
(
  'registry_premium_currency',
  tc_id_from_name('attr_category', 'premium'),
  'NOT IN USE: Currency for premium domains',
  tc_id_from_name('attr_value_type', 'TEXT'),
  NULL::TEXT,
  TRUE
),
-- general category
(
  'default_accreditation',
  tc_id_from_name('attr_category', 'general'),
  'NOT IN USE: Default accreditation',
  tc_id_from_name('attr_value_type', 'TEXT'),
  NULL::TEXT,
  TRUE
),
(
  'provision_retry_backoff_factor',
  tc_id_from_name('attr_category', 'general'),
  'Exponential backoff factor for retrying failed operations',
  tc_id_from_name('attr_value_type', 'INTEGER'),
  4::TEXT,
  FALSE
),
-- provider category
(
  'protocol_type',
  tc_id_from_name('attr_category', 'provider'),
  'NOT IN USE: Protocol type used by the provider',
  tc_id_from_name('attr_value_type', 'TEXT'),
  'EPP'::TEXT,
  FALSE
),
(
  'web_account_password_linked_to_epp',
  tc_id_from_name('attr_category', 'provider'),
  'NOT IN USE: Web account password is linked to EPP',
  tc_id_from_name('attr_value_type', 'BOOLEAN'),
  FALSE::TEXT,
  FALSE
),
(
  'epp_contact_postal_info_type',
  tc_id_from_name('attr_category', 'provider'),
  'NOT IN USE: EPP contact postal info type',
  tc_id_from_name('attr_value_type', 'TEXT_LIST'),
  '{}'::TEXT,
  FALSE
),
-- accreditation category
(
  'accreditation_name',
  tc_id_from_name('attr_category', 'accreditation'),
  'NOT IN USE: Name of the accreditation',
  tc_id_from_name('attr_value_type', 'TEXT'),
  NULL::TEXT,
  TRUE
),
(
  'registrar',
  tc_id_from_name('attr_category', 'accreditation'),
  'NOT IN USE: Registrar name',
  tc_id_from_name('attr_value_type', 'TEXT'),
  NULL::TEXT,
  TRUE
),
(
  'registry',
  tc_id_from_name('attr_category', 'accreditation'),
  'NOT IN USE: Registry name',
  tc_id_from_name('attr_value_type', 'TEXT'),
  'registry'::TEXT,
  FALSE
),
(
  'backend_provider',
  tc_id_from_name('attr_category', 'accreditation'),
  'NOT IN USE: Backend provider',
  tc_id_from_name('attr_value_type', 'TEXT'),
  NULL::TEXT,
  TRUE
),
(
  'sales_tax',
  tc_id_from_name('attr_category', 'accreditation'),
  'NOT IN USE: Sales tax information',
  tc_id_from_name('attr_value_type', 'TEXT'),
  NULL::TEXT,
  TRUE
);
