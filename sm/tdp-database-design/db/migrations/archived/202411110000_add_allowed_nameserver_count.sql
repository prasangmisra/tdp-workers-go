INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES (
           'allowed_nameserver_count',
           (SELECT id FROM attr_category WHERE name='dns'),
           'Range of minimum and maximum required nameservers by registry',
           (SELECT id FROM attr_value_type WHERE name='INTEGER_RANGE'),
           '[2, 13]'::TEXT,
           FALSE
       );