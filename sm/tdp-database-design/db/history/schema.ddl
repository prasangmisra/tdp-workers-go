CREATE SCHEMA IF NOT EXISTS history;

--
-- table: history.domain
-- description: this table lists all deleted or transfered_away domains.
--
CREATE TABLE history.domain (
  reason                  TEXT,   
  id                      UUID NOT NULL PRIMARY KEY,
  tenant_customer_id      UUID,
  tenant_name             TEXT,
  customer_name           TEXT,
  accreditation_tld_id    UUID,
  name                    FQDN,
  auth_info               TEXT,
  roid                    TEXT,
  ry_created_date         TIMESTAMPTZ,
  ry_expiry_date          TIMESTAMPTZ,
  ry_updated_date         TIMESTAMPTZ,
  ry_transfered_date      TIMESTAMPTZ,
  deleted_date            TIMESTAMPTZ,
  expiry_date             TIMESTAMPTZ,
  auto_renew              BOOLEAN,
  secdns_max_sig_life     INT,
  tags                    TEXT[],
  metadata                JSONB,
  uname                   TEXT,
  language                TEXT,
  migration_info          JSONB,
  created_date            TIMESTAMPTZ DEFAULT NOW()
);

-- Make tags and metadata efficiently searchable.
CREATE INDEX ON history.domain USING GIN(tags);
CREATE INDEX ON history.domain USING GIN(metadata);

-- Additional indexes
CREATE INDEX idx_domain_tenant_customer_id ON history.domain(tenant_customer_id);
CREATE INDEX idx_domain_accreditation_tld_id ON history.domain(accreditation_tld_id);
CREATE INDEX idx_domain_name ON history.domain(name);
CREATE INDEX idx_domain_ry_created_date ON history.domain(ry_created_date);
CREATE INDEX idx_domain_ry_expiry_date ON history.domain(ry_expiry_date);
CREATE INDEX idx_domain_ry_updated_date ON history.domain(ry_updated_date);
CREATE INDEX idx_domain_ry_transfered_date ON history.domain(ry_transfered_date);
CREATE INDEX idx_domain_deleted_date ON history.domain(deleted_date);
CREATE INDEX idx_domain_expiry_date ON history.domain(expiry_date);

CREATE TABLE history.secdns_key_data(
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  orig_id     UUID,
  flags       INT,
  protocol    INT,
  algorithm   INT,
  public_key  TEXT
);

CREATE TABLE history.secdns_ds_data(
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  orig_id      UUID,
  key_tag      INT,
  algorithm    INT,
  digest_type  INT,
  digest       TEXT,
  key_data_id  UUID REFERENCES history.secdns_key_data
);

CREATE TABLE history.domain_secdns( 
  id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id     UUID NOT NULL REFERENCES history.domain,
  ds_data_id    UUID REFERENCES history.secdns_ds_data,
  key_data_id   UUID REFERENCES history.secdns_key_data
); 

CREATE INDEX domain_secdns_domain_id_idx ON history.domain_secdns(domain_id);

CREATE TABLE history.contact (
  id                        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  orig_id                   UUID, 
  type_id                   UUID, 
  title                     TEXT,
  org_reg                   TEXT,
  org_vat                   TEXT,
  org_duns                  TEXT,
  tenant_customer_id        UUID,
  email                     Mbox,
  phone                     TEXT,
  phone_ext                 TEXT,
  fax                       TEXT,
  fax_ext                   TEXT,
  country                   TEXT,
  language                  TEXT,  
  tags                      TEXT[],
  documentation             TEXT[],
  short_id                  TEXT,
  metadata                  JSONB,
  migration_info            JSONB
);
  
-- Make tags efficiently searchable.
CREATE INDEX ON history.contact USING GIN(tags);
CREATE INDEX ON history.contact USING GIN(metadata);

-- Additional indexes
CREATE INDEX idx_contact_orig_id ON history.contact(orig_id);
CREATE INDEX idx_contact_type_id ON history.contact(type_id);
CREATE INDEX idx_contact_tenant_customer_id ON history.contact(tenant_customer_id);
CREATE INDEX idx_contact_email ON history.contact(email);
CREATE INDEX idx_contact_country ON history.contact(country);
CREATE INDEX idx_contact_language ON history.contact(language);

CREATE TABLE history.domain_contact (
  id                     UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id              UUID NOT NULL REFERENCES history.domain,
  contact_id             UUID NOT NULL REFERENCES history.contact,
  domain_contact_type_id UUID,
  is_local_presence      BOOLEAN,
  is_privacy_proxy       BOOLEAN,
  is_private             BOOLEAN,
  handle                 TEXT
);  

CREATE INDEX idx_domain_contact_domain_id ON history.domain_contact(domain_id);
CREATE INDEX idx_domain_contact_contact_id ON history.domain_contact(contact_id);
CREATE INDEX idx_domain_contact_domain_contact_type_id ON history.domain_contact(domain_contact_type_id);

--
-- table: history.contact_postal
-- description: Contains the character set dependent attributes of extensible contacts.
--

CREATE TABLE history.contact_postal (
  id                        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  orig_id                   UUID,
  contact_id                UUID REFERENCES history.contact,
  is_international          BOOLEAN,
  first_name                TEXT,
  last_name                 TEXT,
  org_name                  TEXT,
  address1                  TEXT,
  address2                  TEXT,
  address3                  TEXT,
  city                      TEXT,
  postal_code               TEXT,
  state                     TEXT
);

-- Additional indexes
CREATE INDEX idx_contact_postal_contact_id ON history.contact_postal(contact_id);
CREATE INDEX idx_contact_postal_is_international ON history.contact_postal(is_international);
CREATE INDEX idx_contact_postal_city ON history.contact_postal(city);
CREATE INDEX idx_contact_postal_postal_code ON history.contact_postal(postal_code);
CREATE INDEX idx_contact_postal_state ON history.contact_postal(state);

--
-- table: history.contact_attribute
-- description: holds additional contact attributes all represented as TEXT
--

CREATE TABLE history.contact_attribute (
  id                        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  attribute_id              UUID,
  attribute_type_id         UUID,
  contact_id                UUID REFERENCES history.contact,
  value                     TEXT
);

-- Additional indexes
CREATE INDEX idx_contact_attribute_attribute_id ON history.contact_attribute(attribute_id);
CREATE INDEX idx_contact_attribute_attribute_type_id ON history.contact_attribute(attribute_type_id);
CREATE INDEX idx_contact_attribute_contact_id ON history.contact_attribute(contact_id);

CREATE TABLE history.host (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  orig_id                 UUID,
  tenant_customer_id      UUID,
  name                    TEXT,
  domain_id               UUID, -- parent domain id --> NOT the same as domain_host
  tags                    TEXT[],
  metadata                JSONB
);

-- Make tags and metadata efficiently searchable.
CREATE INDEX ON history.host USING GIN(tags);
CREATE INDEX ON history.host USING GIN(metadata);

-- Additional indexes
CREATE INDEX idx_host_orig_id ON history.host(orig_id);
CREATE INDEX idx_host_tenant_customer_id ON history.host(tenant_customer_id);
CREATE INDEX idx_host_name ON history.host(name);
CREATE INDEX idx_host_domain_id ON history.host(domain_id);

CREATE TABLE history.domain_host( -- not copy 
  id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id UUID NOT NULL REFERENCES history.domain,
  host_id   UUID NOT NULL REFERENCES history.host
); 

CREATE INDEX idx_domain_host_domain_id ON history.domain_host(domain_id);
CREATE INDEX idx_domain_host_host_id ON history.domain_host(host_id);

--
-- table: history.host_addr
-- description: IPv4 or IPv6 address of a host
--

CREATE TABLE history.host_addr (  
  id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  host_id UUID NOT NULL REFERENCES history.host,
  address INET
);

-- Additional indexes
CREATE INDEX idx_host_addr_host_id ON history.host_addr(host_id);
CREATE INDEX idx_host_addr_address ON history.host_addr(address);

COMMENT ON COLUMN history.host.orig_id IS '
This is original_id from host table; For tables with ids that can be used multiple times - contact.
';

COMMENT ON COLUMN history.contact_postal.orig_id IS '
This is original_id from contact_postal table; For tables with ids that can be used multiple times - contact.
';

COMMENT ON COLUMN history.contact.orig_id IS '
This is original_id from contact table; For tables with ids that can be used multiple times - contact.
';

COMMENT ON COLUMN history.domain.reason IS '
This is the reason to delete domain from the system: deletion or transfer_away. It is nullable.
Record can be Deleted or Transfered. 
';
