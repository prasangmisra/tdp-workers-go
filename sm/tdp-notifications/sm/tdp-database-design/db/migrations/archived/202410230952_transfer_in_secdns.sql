-- create if not exist
DO $$ BEGIN
    CREATE TYPE secdns_data_type AS ENUM ('ds_data', 'key_data');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;


ALTER TABLE IF EXISTS provision_domain_transfer_in ADD COLUMN IF NOT EXISTS secdns_type secdns_data_type;

CREATE TABLE IF NOT EXISTS transfer_in_domain_secdns_ds_data (
    provision_domain_transfer_in_id UUID NOT NULL REFERENCES provision_domain_transfer_in,
    PRIMARY KEY(id)
)INHERITS(secdns_ds_data);

CREATE TABLE IF NOT EXISTS transfer_in_domain_secdns_key_data (
    provision_domain_transfer_in_id UUID NOT NULL REFERENCES provision_domain_transfer_in,
    PRIMARY KEY(id)
)INHERITS(secdns_key_data);

-- Composite index for domain_id and ds_data_id
CREATE INDEX IF NOT EXISTS idx_transfer_in_domain_secdns_domain_ds
    ON transfer_in_domain_secdns_ds_data(provision_domain_transfer_in_id);

-- Composite index for domain_id and key_data_id
CREATE INDEX IF NOT EXISTS idx_transfer_in_domain_secdns_domain_key
    ON transfer_in_domain_secdns_key_data(provision_domain_transfer_in_id);