--
-- Remove existing unique constraints to the tld_validation_rule table
--

ALTER TABLE tld_validation_rule DROP CONSTRAINT IF EXISTS tld_validation_rule_order_type_id_validation_rule_id_key;
ALTER TABLE tld_validation_rule DROP CONSTRAINT IF EXISTS tld_validation_rule_tld_id_order_type_id_validation_rule_id_key;
ALTER TABLE tld_validation_rule DROP CONSTRAINT IF EXISTS tld_validation_rule_tld_id_validation_rule_id_key;

--
-- Add new unique constraints to the tld_validation_rule table
--
CREATE UNIQUE INDEX IF NOT EXISTS tld_validation_rule_tld_id_order_type_id_validation_rule_id_idx ON tld_validation_rule (tld_id, order_type_id, validation_rule_id)
    WHERE tld_id IS NOT NULL AND order_type_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS tld_validation_rule_tld_id_validation_rule_id_idx ON tld_validation_rule (tld_id, validation_rule_id)
    WHERE tld_id IS NOT NULL AND order_type_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS tld_validation_rule_order_type_id_validation_rule_id_idx ON tld_validation_rule (order_type_id, validation_rule_id)
    WHERE tld_id IS NULL AND order_type_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS tld_validation_rule_validation_rule_id_idx ON tld_validation_rule (validation_rule_id)
    WHERE tld_id IS NULL AND order_type_id IS NULL;

--
-- Drop existing foreign key constraints
--
ALTER TABLE tld_validation_rule DROP CONSTRAINT IF EXISTS tld_validation_rule_validation_rule_id_fkey;

--
-- Add foreign key constraints with ON DELETE CASCADE
--
ALTER TABLE tld_validation_rule
    ADD CONSTRAINT tld_validation_rule_validation_rule_id_fkey FOREIGN KEY (validation_rule_id) REFERENCES validation_rule(id) ON DELETE CASCADE;