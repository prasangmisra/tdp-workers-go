--
-- Add unique constraints to the tld_validation_rule table to cover for nullable columns
--

ALTER TABLE tld_validation_rule ADD UNIQUE (tld_id, validation_rule_id);
ALTER TABLE tld_validation_rule ADD UNIQUE (order_type_id, validation_rule_id);

--
-- Add is_active column to the validation_rule table
--

ALTER TABLE validation_rule ADD COLUMN is_active BOOLEAN DEFAULT TRUE;