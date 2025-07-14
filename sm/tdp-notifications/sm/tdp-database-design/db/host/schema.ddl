--
-- table: host
-- description: host objects
--
-- TODO: write a constraint to check that if the domain_id is set
-- that the domain is also owned by this tenant_customer
--

CREATE TABLE host (
    id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_customer_id      UUID NOT NULL REFERENCES tenant_customer,
    name                    TEXT NOT NULL,
    domain_id               UUID,
    tags                    TEXT[],
    metadata                JSONB DEFAULT '{}'::JSONB,
    UNIQUE(tenant_customer_id,name)
) INHERITS (class.audit_trail);

-- Make tags and metadata efficiently searchable.
CREATE INDEX ON host USING GIN(tags);
CREATE INDEX ON host USING GIN(metadata);

COMMENT ON TABLE host IS 'host objects';
COMMENT ON COLUMN host.domain_id IS 'if the host is a sub domain of a registered name, we will add the reference here.';

--
-- table: host_addr
-- description: IPv4 or IPv6 address of a host
--

CREATE TABLE host_addr (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    host_id UUID NOT NULL REFERENCES host ON DELETE CASCADE,
    address INET,
    UNIQUE(host_id, address)
) INHERITS (class.audit_trail);
