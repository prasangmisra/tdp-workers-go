-- insert new attribute keys
INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null
)
VALUES(
    'is_contact_update_supported',
    (SELECT id FROM attr_category WHERE name='contact'),
    'Registry supports updating contact via update command',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    TRUE
),(
    'is_owner_contact_change_supported',
    (SELECT id FROM attr_category WHERE name='contact'),
    'Registry supports owner change update',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    FALSE::TEXT,
    TRUE
) ON CONFLICT DO NOTHING;
