ALTER TABLE IF EXISTS domain_contact ALTER COLUMN handle DROP NOT NULL;

COMMENT ON COLUMN contact.metadata IS 'Contains migration information as example - {"data_source": "Enom", "invalid_fields": [country], "migration_lost_handle": true}';

