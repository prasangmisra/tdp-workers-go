-- Remove the max_nameservers and min_nameservers settings
DELETE FROM attr_value
WHERE key_id IN (
  SELECT id
  FROM attr_key
  WHERE name IN ('max_nameservers', 'min_nameservers')
);

DELETE FROM attr_key
WHERE name IN ('max_nameservers', 'min_nameservers');
