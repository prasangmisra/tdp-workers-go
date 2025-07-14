-- function: validate_escrow_config()
-- description: this function validates the escrow_config record before inserting or updating it
CREATE OR REPLACE FUNCTION validate_escrow_config() RETURNS TRIGGER AS $$
BEGIN
    -- Validation for deposit method
    IF NOT (NEW.deposit_method IN ('SFTP')) THEN
        RAISE EXCEPTION 'Invalid deposit method. Must be ''SFTP''.';
    END IF;

    -- Validation for encryption method
    IF NOT (NEW.encryption_method IN ('GPG')) THEN
        RAISE EXCEPTION 'Invalid encryption method. Must be ''GPG''.';
    END IF;

    -- Validation for authentication method
    IF NOT (NEW.authentication_method IN ('SSH_KEY', 'PASSWORD')) THEN
        RAISE EXCEPTION 'Invalid authentication method. Must be either ''SSH_KEY'' or ''PASSWORD''.';
    END IF;

    -- Validation for authentication method and associated fields
    IF NEW.authentication_method = 'PASSWORD' AND NEW.username IS NULL THEN
        RAISE EXCEPTION 'For password authentication, username must be provided.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE SCHEMA IF NOT EXISTS escrow;

--
-- table: escrow_config
-- description: this table stores the configuration for the escrow platform.
--
CREATE TABLE IF NOT EXISTS escrow.escrow_config (
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,   -- Unique identifier
  tenant_id             UUID NOT NULL REFERENCES tenant,                       -- Foreign key to tenant table
  iana_id               TEXT NOT NULL,                                         -- IANA-assigned registry ID
  deposit_method        TEXT NOT NULL DEFAULT 'SFTP',                          -- e.g. 'SFTP', 'FTPS', 'HTTPS', 'MFT', 'EOD'
  host                  TEXT NOT NULL,                                         -- Hostname or IP of the deposit server
  port                  INTEGER,                                               -- Optional port (e.g., 22 for SFTP)
  path                  TEXT,                                                  -- Optional path for protocols like HTTPS
  username              TEXT,                                                  -- Username for authentication
  authentication_method TEXT NOT NULL DEFAULT 'SSH_KEY',                       -- Authentication method: 'SSH_KEY', 'PASSWORD', 'TOKEN'
  encryption_method     TEXT NOT NULL DEFAULT 'GPG',                           -- Encryption method: 'GPG', 'AES-256'
  notes                 TEXT,                                                  -- Optional notes for additional information
  UNIQUE (tenant_id)                                                           -- Ensure only one record per tenant
) INHERITS (class.audit_trail);

-- validate escrow_config record
CREATE OR REPLACE TRIGGER trigger_validate_escrow_config
    BEFORE INSERT OR UPDATE ON escrow.escrow_config
    FOR EACH ROW EXECUTE FUNCTION validate_escrow_config();

CREATE INDEX IF NOT EXISTS idx_escrow_config_tenant_id ON escrow.escrow_config (tenant_id);

--
-- table: escrow_status
-- description: this table stores the status of the escrow process.
--
CREATE TABLE IF NOT EXISTS escrow.escrow_status (
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  descr       TEXT,
  is_success  BOOLEAN NOT NULL,
  is_final    BOOLEAN NOT NULL,
  UNIQUE (name)
);

--
-- table: escrow_step
-- description: this table stores the steps in the escrow workflow.
--
CREATE TABLE IF NOT EXISTS escrow.escrow_step (
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  descr       TEXT,
  UNIQUE (name)
);

--
-- table: escrow
-- description: this table stores the escrow record.
--
CREATE TABLE IF NOT EXISTS escrow.escrow (
    id                UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    config_id         UUID NOT NULL REFERENCES escrow.escrow_config,
    start_date        TIMESTAMPTZ,
    end_date          TIMESTAMPTZ,
    status_id         UUID NOT NULL DEFAULT tc_id_from_name('escrow.escrow_status', 'pending') 
                      REFERENCES escrow.escrow_status,
    step              UUID REFERENCES escrow.escrow_step,
    metadata          JSONB DEFAULT '{}'::JSONB
) INHERITS (class.audit_trail);


-- Insert initial data into escrow_status
INSERT INTO escrow.escrow_status(name,descr,is_success,is_final)
    VALUES
        ('pending','Newly created escrow record',true,false),
        ('processing','Escrow record is being processed',false,false),
        ('completed','Escrow record was completed',true,true),
        ('failed','Escrow record failed',false,true)
    ON CONFLICT DO NOTHING;


-- Insert initial data into escrow_step
INSERT INTO escrow.escrow_step(name,descr)
    VALUES
        ('hashing','Hashing the escrow data for integrity verification'),
        ('compression','Compressing the escrow data to reduce size'),
        ('encryption','Encrypting the escrow data for security'),
        ('upload','Uploading the escrow data to the designated server')
    ON CONFLICT DO NOTHING;
