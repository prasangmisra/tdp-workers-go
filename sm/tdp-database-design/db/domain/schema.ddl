
--
-- table: domain_contact_type
-- description: this table list the possible contact types of a domains
--

CREATE TABLE domain_contact_type (
  id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name      TEXT NOT NULL,
  descr     TEXT,
  UNIQUE (name)
);

--
-- table: domain
-- description: this table lists all active domains.
--

-- need domain status field and a domain history table, audit trail may be able to help
CREATE TABLE domain (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_customer_id      UUID NOT NULL REFERENCES tenant_customer,
  accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
  name                    FQDN NOT NULL,
  auth_info               TEXT,
  roid                    TEXT,
  ry_created_date         TIMESTAMPTZ,
  ry_expiry_date          TIMESTAMPTZ,
  ry_updated_date         TIMESTAMPTZ,
  ry_transfered_date      TIMESTAMPTZ,
  deleted_date            TIMESTAMPTZ,
  expiry_date             TIMESTAMPTZ NOT NULL,
  auto_renew              BOOLEAN NOT NULL DEFAULT TRUE,
  secdns_max_sig_life     INT,
  tags                    TEXT[],
  metadata                JSONB DEFAULT '{}'::JSONB,
  uname                   TEXT,
  language                TEXT,
  migration_info          JSONB DEFAULT '{}',
  UNIQUE(name)
) INHERITS (class.audit_trail);

-- Make tags and metadata efficiently searchable.
CREATE INDEX ON domain USING GIN(tags);
CREATE INDEX ON domain USING GIN(metadata);
COMMENT ON COLUMN domain.migration_info IS 'Contains migration information as example - {"allowed_nameserver_count_issue": true}';


--
-- table: domain_contact
-- description: this table joins domains and contacts
--

CREATE TABLE domain_contact (
  id                     UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id              UUID NOT NULL REFERENCES domain ON DELETE CASCADE,
  contact_id             UUID NOT NULL REFERENCES contact,
  domain_contact_type_id UUID NOT NULL REFERENCES domain_contact_type,
  is_local_presence      BOOLEAN NOT NULL DEFAULT FALSE,
  is_privacy_proxy       BOOLEAN NOT NULL DEFAULT FALSE,
  is_private             BOOLEAN NOT NULL DEFAULT FALSE,
  handle                 TEXT NULL,
  CONSTRAINT domain_contact_domain_id_type_id_is_private_privacy_local_key UNIQUE (domain_id, domain_contact_type_id, is_private, is_privacy_proxy, is_local_presence)
) INHERITS (class.audit_trail);

--
-- table: domain_host
-- description: this table joins domains and hosts
--

CREATE TABLE domain_host (
  id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id UUID NOT NULL REFERENCES domain ON DELETE CASCADE,
  host_id   UUID NOT NULL REFERENCES host,
  UNIQUE(domain_id, host_id)
) INHERITS (class.audit_trail);


--
-- table: domain_rgp_status
-- description: this table joins domain and rgp_status
--

CREATE TABLE domain_rgp_status
(
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    domain_id           UUID NOT NULL REFERENCES domain ON DELETE CASCADE,
    status_id           UUID NOT NULL REFERENCES rgp_status,
    created_date        TIMESTAMPTZ DEFAULT NOW(),
    expiry_date         TIMESTAMPTZ NOT NULL
); 

CREATE INDEX ON domain_rgp_status(domain_id);
CREATE INDEX ON domain_rgp_status(status_id);
CREATE INDEX ON domain_rgp_status(expiry_date);

CREATE TRIGGER domain_rgp_status_set_expiration_tg
    BEFORE INSERT ON domain_rgp_status 
    FOR EACH ROW  WHEN (NOT is_data_migration() ) EXECUTE PROCEDURE domain_rgp_status_set_expiry_date();

--
-- table: domain_lock
-- description: this table joins domain and lock_type
--

CREATE TABLE domain_lock
(
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    domain_id           UUID NOT NULL REFERENCES domain ON DELETE CASCADE,
    type_id             UUID NOT NULL REFERENCES lock_type,
    is_internal         BOOLEAN NOT NULL DEFAULT FALSE, -- set by registrar
    created_date        TIMESTAMPTZ DEFAULT NOW(),
    expiry_date         TIMESTAMPTZ,
    UNIQUE(domain_id, type_id, is_internal),
    CHECK( 
      expiry_date IS NULL OR
      ( 
        expiry_date IS NOT NULL  -- expiry date can be set on internal lock only
        AND is_internal
      ) 
    )
); 

CREATE INDEX ON domain_lock(domain_id);
CREATE INDEX ON domain_lock(type_id);

CREATE TABLE secdns_key_data
(
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  flags       INT NOT NULL,
  protocol    INT NOT NULL DEFAULT 3,
  algorithm   INT NOT NULL,
  public_key  TEXT NOT NULL,
  CONSTRAINT flags_ok CHECK (
    -- equivalent to binary literal 0b011111110111111
    (flags & 65471) = 0
  ),
  CONSTRAINT algorithm_ok CHECK (
    algorithm IN (1,2,3,4,5,6,7,8,10,12,13,14,15,16,17,23,252,253,254)
  )
);

CREATE TABLE secdns_ds_data
(
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  key_tag      INT NOT NULL,
  algorithm    INT NOT NULL,
  digest_type  INT NOT NULL DEFAULT 1,
  digest       TEXT NOT NULL,

  key_data_id UUID REFERENCES secdns_key_data ON DELETE CASCADE,
  CONSTRAINT algorithm_ok CHECK (
    algorithm IN (1,2,3,4,5,6,7,8,10,12,13,14,15,16,17,23,252,253,254)
  ),
  CONSTRAINT digest_type_ok CHECK (
    digest_type IN (1,2,3,4,5,6)
  )
);

CREATE TABLE domain_secdns
(
  id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id     UUID NOT NULL REFERENCES domain ON DELETE CASCADE,
  ds_data_id    UUID REFERENCES secdns_ds_data ON DELETE CASCADE,
  key_data_id   UUID REFERENCES secdns_key_data ON DELETE CASCADE,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  )
);

CREATE INDEX domain_secdns_domain_id_idx ON domain_secdns(domain_id);

CREATE TRIGGER domain_secdns_check_single_record_type_tg
    BEFORE INSERT ON domain_secdns
    FOR EACH ROW EXECUTE PROCEDURE validate_secdns_type('domain_secdns', 'domain_id');
