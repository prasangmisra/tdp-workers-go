-- Insert new attribute key
INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES(
    'rdp_enabled',
    tc_id_from_name('attr_category', 'order'),
    'RDP filters enabled',
    tc_id_from_name('attr_value_type', 'BOOLEAN'),
    FALSE::TEXT,
    FALSE
) ON CONFLICT DO NOTHING;
