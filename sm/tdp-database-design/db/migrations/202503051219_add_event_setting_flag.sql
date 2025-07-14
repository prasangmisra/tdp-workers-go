INSERT INTO attr_category(name,descr,parent_id)
VALUES
    ('event','event Information',(SELECT id FROM attr_category WHERE name='tld'))
ON CONFLICT DO NOTHING;

INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES
    (
        'is_event_creation_enabled',
        tc_id_from_name('attr_category', 'event'),
        'flag to enable event creation',
        tc_id_from_name('attr_value_type', 'BOOLEAN'),
        FALSE::TEXT,
        FALSE
    ) ON CONFLICT DO NOTHING ;