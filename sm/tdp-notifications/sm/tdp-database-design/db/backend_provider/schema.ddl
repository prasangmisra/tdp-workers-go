CREATE TABLE epp_extension(
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    decr            TEXT,
    doc_url         TEXT,
    is_implemented  BOOLEAN NOT NULL                
) INHERITS(class.audit);

--
-- table: registry
-- description: this table lists all registry operators (XYZ, Verisign, etc.)
--

CREATE TABLE registry (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  business_entity_id UUID NOT NULL REFERENCES business_entity(id),
  name               TEXT NOT NULL,
  descr              TEXT,
  UNIQUE(business_entity_id),
  UNIQUE(name)
) INHERITS (class.audit_trail);

--
-- table: tld_type
-- description: this table lists all types of top level domains such as generic, country-code
--

CREATE TABLE tld_type (
    id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name       TEXT NOT NULL,
    descr       TEXT,
    UNIQUE(name)
)INHERITS (class.audit_trail); 

--
-- table: tld
-- description: this table lists all tlds.
--

CREATE TABLE tld (
  id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  registry_id         UUID NOT NULL REFERENCES registry(id),
  parent_tld_id       UUID REFERENCES tld,
  name                TEXT NOT NULL,
  type_id             UUID NOT NULL REFERENCES tld_type,
  UNIQUE(name)
) INHERITS (class.audit_trail);

COMMENT ON COLUMN tld.name IS          'The top level domain without a leading dot';
COMMENT ON COLUMN tld.parent_tld_id IS 'If top level domain is for instance co.uk this foreign key refers to uk.';

--
-- table: provider
-- description: this table lists all backend providers.
--

CREATE TABLE provider (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  business_entity_id UUID NOT NULL REFERENCES business_entity(id),
  name               TEXT NOT NULL,
  descr              TEXT,
  UNIQUE(business_entity_id),
  UNIQUE(name)
) INHERITS (class.audit_trail);


--
-- table: provider_instance
-- description: this table joins backend providers to instances.
--

CREATE TABLE provider_instance (
  id                            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_id                   UUID NOT NULL REFERENCES provider,
  name                          TEXT NOT NULL UNIQUE,
  descr                         TEXT,
  is_proxy                      BOOLEAN
) INHERITS (class.audit_trail);


COMMENT ON TABLE provider_instance IS 
'within a backend provider, there can be multiple instances, which could represent
customers or simply buckets where the tlds are placed, each one of these are considered
instances each one with its own credentials, etc.';
COMMENT ON COLUMN provider_instance.is_proxy IS 'whether this provider is forwarding requests to another (hexonet, opensrs, etc.)';


--
-- table: provider_instance_tld
-- description: this table joins backend provider instances to tlds.
--

CREATE TABLE provider_instance_tld (
  id                           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_instance_id         UUID NOT NULL REFERENCES provider_instance,
  tld_id                       UUID NOT NULL REFERENCES tld,
  service_range                TSTZRANGE NOT NULL DEFAULT '(-Infinity,Infinity)',
  EXCLUDE USING GIST (
    provider_instance_id WITH  =,
    tld_id WITH =,
    service_range WITH &&
  )
) INHERITS (class.audit_trail);

COMMENT ON COLUMN provider_instance_tld.service_range IS 
'This attribute serves to limit the applicablity of a relation over time.
A constraint named service_range_unique ensures that for a given instance_id, tld_id,
there is no overlap of the service range.';


-- table: supported_protocol
-- description: this table lists the backend provider protocols supported by the registration system  
--

CREATE TABLE supported_protocol (
  id   UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT,
  descr TEXT,
  UNIQUE(name)
);

COMMENT ON COLUMN supported_protocol.name IS 'Name of a protocol, like ''EPP'', ''Hexonet HTTP'', ...';

CREATE TABLE provider_protocol (
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_id           UUID NOT NULL REFERENCES provider,
  supported_protocol_id UUID NOT NULL REFERENCES supported_protocol,
  is_enabled            BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE(provider_id,supported_protocol_id)
) INHERITS(class.audit_trail);



CREATE TABLE certificate_authority(
      id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
      name      TEXT NOT NULL UNIQUE,
      descr     TEXT,
      cert      TEXT,
      service_range       TSTZRANGE NOT NULL DEFAULT '(-Infinity,Infinity)'
) INHERITS(class.audit);

CREATE TABLE tenant_cert(
    id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name      TEXT,
    cert      TEXT,
    key       TEXT,
    ca_id     UUID NOT NULL REFERENCES certificate_authority,
    service_range       TSTZRANGE NOT NULL DEFAULT '(-Infinity,Infinity)'
) INHERITS(class.audit);

CREATE TABLE class.epp_setting(
  host              TEXT,
  port              INT DEFAULT 700 CHECK(port > 0 AND port < 65536),
  conn_min          INT DEFAULT 1,
  conn_max          INT DEFAULT 10,
  ssl_verify_host   BOOLEAN,
  ssl_verify        BOOLEAN,
  xml_verify_schema BOOLEAN,
  keepalive_seconds INT DEFAULT 20,
  session_max_cmd INT,
  session_max_sec INT,
  CHECK( 
    conn_min > 0 AND conn_max > 0
    AND conn_max >= conn_min
  )
);
COMMENT ON column class.epp_setting.ssl_verify_host IS 'whether to use SSL host verification';
COMMENT ON column class.epp_setting.ssl_verify IS 'whether to use SSL server verification';
COMMENT ON column class.epp_setting.xml_verify_schema IS 'whether to use provided XSD schema for XML verification';
COMMENT ON column class.epp_setting.keepalive_seconds IS 'amount of time between each keepalive command';
COMMENT ON column class.epp_setting.session_max_sec IS 'number of seconds until session expires and reconnection required. NULL represents no limit.';
COMMENT ON column class.epp_setting.session_max_cmd IS 'max number of commands allowed in a session until reconnection required. NULL represents no limit.';

CREATE TABLE provider_instance_epp (
  id                            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_instance_id          UUID NOT NULL REFERENCES provider_instance,
  UNIQUE(provider_instance_id),
  CHECK(host IS NOT NULL),
  CHECK(port IS NOT NULL)
) INHERITS(class.epp_setting);

CREATE TABLE provider_instance_epp_ext(
  id                        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_instance_epp_id  UUID NOT NULL REFERENCES provider_instance_epp,
  epp_extension_id          UUID NOT NULL REFERENCES epp_extension,
  UNIQUE(provider_instance_epp_id,epp_extension_id)
) INHERITS(class.audit_trail);


CREATE TABLE provider_instance_http (
  id                            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_instance_id          UUID NOT NULL REFERENCES provider_instance,
  url                           TEXT,
  api_key                       TEXT,
  UNIQUE(provider_instance_id)
);

-- table: accreditation
-- description: this table links tenants to their default backend providers
--

CREATE TABLE accreditation (
  id                   UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name                 TEXT NOT NULL UNIQUE,
  tenant_id            UUID NOT NULL REFERENCES tenant,
  provider_instance_id UUID NOT NULL REFERENCES provider_instance,
  service_range        TSTZRANGE NOT NULL DEFAULT '(-Infinity,Infinity)',
  registrar_id         TEXT NOT NULL
) INHERITS (class.audit_trail);

COMMENT ON COLUMN accreditation.service_range IS 'This attribute serves to limit the applicability of a relation over time.';

CREATE TABLE accreditation_epp(
  id                   UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  accreditation_id     UUID NOT NULL REFERENCES accreditation,
  cert_id              UUID REFERENCES tenant_cert,
  clid                 TEXT NOT NULL,
  pw                   TEXT NOT NULL
) INHERITS(class.audit_trail,class.epp_setting);


CREATE TABLE accreditation_tld(
    id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    accreditation_id            UUID NOT NULL REFERENCES accreditation,
    provider_instance_tld_id    UUID NOT NULL REFERENCES provider_instance_tld,
    is_default                  BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE(accreditation_id,provider_instance_tld_id)
);

CREATE UNIQUE INDEX ON 
  accreditation_tld(accreditation_id,provider_instance_tld_id) WHERE is_default;
COMMENT ON TABLE accreditation_tld IS 'tlds covered by an accreditation';

--
-- table: rgp_status
-- description: this table lists all posible RGP statuses
--

CREATE TABLE rgp_status (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  epp_name   TEXT NOT NULL, 
  descr      TEXT NOT NULL,
  UNIQUE (name)
);
