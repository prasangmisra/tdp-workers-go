-- Rename the attribute key in the attr_key table
UPDATE attr_key
SET name = 'authcode_acceptance_criteria'
WHERE name = 'authcode_regex';
