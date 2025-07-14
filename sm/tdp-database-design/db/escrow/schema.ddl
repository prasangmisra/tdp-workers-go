CREATE SCHEMA IF NOT EXISTS escrow;

--
-- table: escrow_config
-- description: this table stores the configuration for the escrow platform.
--
CREATE TABLE escrow.escrow_config (
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

CREATE INDEX idx_escrow_config_tenant_id ON escrow.escrow_config (tenant_id);

--
-- table: escrow_status
-- description: this table stores the status of the escrow process.
--
CREATE TABLE escrow.escrow_status (
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
CREATE TABLE escrow.escrow_step (
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  descr       TEXT,
  UNIQUE (name)
);

--
-- table: escrow
-- description: this table stores the escrow record.
--
CREATE TABLE escrow.escrow (
    id                UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    config_id         UUID NOT NULL REFERENCES escrow.escrow_config,
    start_date        TIMESTAMPTZ,
    end_date          TIMESTAMPTZ,
    status_id         UUID NOT NULL DEFAULT tc_id_from_name('escrow.escrow_status', 'pending') 
                      REFERENCES escrow.escrow_status,
    step_id           UUID REFERENCES escrow.escrow_step,
    metadata          JSONB DEFAULT '{}'::JSONB
) INHERITS (class.audit_trail);
