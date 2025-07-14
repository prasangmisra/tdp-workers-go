-- remove period attribute keys
DELETE FROM attr_key WHERE name = 'allowed_renew_periods';
DELETE FROM attr_key WHERE name = 'renewal';
DELETE FROM attr_key WHERE name = 'registration';

-- Insert new attribute keys for allowed periods
INSERT INTO attr_key(
  name,
  category_id,
  descr,
  value_type_id,
  default_value,
  allow_null
) VALUES 
(
  'allowed_registration_periods',
  (SELECT id FROM attr_category WHERE name='lifecycle'),
  'List of allowed registration periods',
  (SELECT id FROM attr_value_type WHERE name='INTEGER_LIST'),
  '{1,2,3,4,5,6,7,8,9,10}'::TEXT,
  FALSE
),
(
  'allowed_renewal_periods',
  (SELECT id FROM attr_category WHERE name='lifecycle'),
  'List of allowed renewal periods',
  (SELECT id FROM attr_value_type WHERE name='INTEGER_LIST'),
  '{1,2,3,4,5,6,7,8,9,10}'::TEXT,
  FALSE
) ON CONFLICT DO NOTHING;


