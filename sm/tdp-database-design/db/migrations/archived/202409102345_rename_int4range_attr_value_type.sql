UPDATE attr_value_type SET name = 'INTEGER_RANGE' WHERE name = 'INT4RANGE';

UPDATE attr_key SET value_type_id = (SELECT id FROM attr_value_type WHERE name='INTEGER_RANGE')
WHERE name = 'domain_length';

UPDATE attr_key SET value_type_id = (SELECT id FROM attr_value_type WHERE name='INTEGER_RANGE')
WHERE name = 'authcode_length';
