INSERT INTO attr_category(name,descr)
    VALUES
        ('provider','Provider Settings'),
        ('accreditation','Accreditation Settings')
    ON CONFLICT DO NOTHING;

INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES
-- order category
(
    'outgoing_transfer_standard_response',
    tc_id_from_name('attr_category', 'order'),
    'NOT IN USE: Standard response for outgoing transfers',
    tc_id_from_name('attr_value_type', 'TEXT'),
    NULL::TEXT,
    TRUE
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
    'authcode_acceptance_criteria',
    tc_id_from_name('attr_category', 'general'),
    'NOT IN USE: Regex pattern for authcode acceptance criteria',
    tc_id_from_name('attr_value_type', 'TEXT'),
    '.*'::TEXT,
    FALSE
),
(
    'default_accreditation',
    tc_id_from_name('attr_category', 'general'),
    'NOT IN USE: Default accreditation',
    tc_id_from_name('attr_value_type', 'TEXT'),
    NULL::TEXT,
    TRUE
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
)
ON CONFLICT DO NOTHING;
