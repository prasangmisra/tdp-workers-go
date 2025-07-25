--
-- table: hosting_product
-- description: list of external hosting products supported
--
CREATE TABLE hosting_product (
    id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name                    TEXT NOT NULL,
    is_active               BOOLEAN NOT NULL DEFAULT FALSE
) INHERITS (class.audit);


--
-- table: hosting_component_type
-- description: this table lists posible component types
--

CREATE TABLE hosting_component_type (
  id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name      TEXT NOT NULL,
  descr     TEXT,
  UNIQUE (name)
);

--
-- table: domain_contact_type
-- description: this table list the possible components
--

CREATE TABLE hosting_component (
  id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  type_id   UUID NOT NULL REFERENCES hosting_component_type,
  name      TEXT NOT NULL,
  descr     TEXT,
  UNIQUE (name)
);



--
-- table: hosting_product_component
-- description: product can have zero or more components associated
--

CREATE TABLE hosting_product_component (
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id      UUID NOT NULL REFERENCES hosting_product,
    component_id    UUID NOT NULL REFERENCES hosting_component
) inherits (class.audit_trail);


--
-- table: hosting_region
-- description: list of regions supported for web hosting
--
CREATE TABLE hosting_region (
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name            TEXT NOT NULL,
    location        TEXT NOT NULL,
    descr           TEXT,
    is_enabled      BOOLEAN NOT NULL DEFAULT FALSE
) INHERITS (class.audit);

--
-- table: hosting_client
-- description: client (end customer) for whom the web hosting is to be provisioned
--
CREATE TABLE hosting_client (
    id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_customer_id      UUID NOT NULL REFERENCES tenant_customer,
    external_client_id      TEXT,
    name                    TEXT,
    email                   mbox NOT NULL,
    username                TEXT,
    password                TEXT,
    is_active               BOOLEAN NOT NULL DEFAULT FALSE
) INHERITS (class.audit_trail);
COMMENT ON COLUMN hosting_client.external_client_id IS 'Unique ID generated by the hosting system';

--
-- table: hosting_certificate
-- description: ssl certificate if provided by the client
--
CREATE TABLE hosting_certificate (
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    body            TEXT NOT NULL,
    chain           TEXT,
    private_key     TEXT NOT NULL,
    not_before      TIMESTAMPTZ NOT NULL,
    not_after       TIMESTAMPTZ NOT NULL
) inherits (class.audit_trail);

--
-- table: hosting_status
-- description: this table lists the possible hosting statuses.
--

CREATE TABLE hosting_status (
       id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
       name       TEXT NOT NULL,
       descr      TEXT NOT NULL,
       UNIQUE (name)
);

--
-- table: hosting
-- description: contains hosting details
--
CREATE TABLE hosting (
    id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    domain_name             FQDN NOT NULL,
    product_id              UUID NOT NULL REFERENCES hosting_product,
    region_id               UUID NOT NULL REFERENCES hosting_region,
    client_id               UUID NOT NULL REFERENCES hosting_client,
    tenant_customer_id      UUID NOT NULL REFERENCES tenant_customer,
    certificate_id          UUID REFERENCES hosting_certificate,
    external_order_id       TEXT,
    status                  TEXT REFERENCES hosting_status(name),
    hosting_status_id       UUID REFERENCES hosting_status,
    descr                   TEXT,
    is_active               BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted              BOOLEAN NOT NULL DEFAULT FALSE,
    tags                    TEXT[],
    metadata                JSONB DEFAULT '{}'::JSON
) INHERITS (class.audit_trail);
COMMENT ON COLUMN hosting.external_order_id IS 'Unique Order ID generated by the hosting system';

CREATE INDEX ON hosting USING GIN(tags);

---------------- backward compatibility of status and hosting_status_id ----------------

CREATE OR REPLACE FUNCTION force_hosting_status_id_from_name() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.status IS NOT NULL THEN
        NEW.hosting_status_id = tc_id_from_name('hosting_status', NEW.status);
    ELSE
        NEW.hosting_status_id = NULL;
    END IF;

RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER hosting_insert_hosting_status_id_from_name_tg
    BEFORE INSERT ON hosting
    FOR EACH ROW WHEN ( NEW.hosting_status_id IS NULL AND NEW.status IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_id_from_name();

CREATE TRIGGER hosting_update_hosting_status_id_from_name_tg
    BEFORE UPDATE OF status ON hosting
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_id_from_name();


CREATE OR REPLACE FUNCTION force_hosting_status_name_from_id() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.hosting_status_id IS NOT NULL THEN
        NEW.status = tc_name_from_id('hosting_status', NEW.hosting_status_id);
    ELSE
        NEW.status = NULL;
    END IF;

RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER hosting_insert_hosting_status_name_from_id_tg
    BEFORE INSERT ON hosting
    FOR EACH ROW WHEN ( NEW.status IS NULL AND NEW.hosting_status_id IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_name_from_id();

CREATE TRIGGER hosting_update_hosting_status_name_from_id_tg
    BEFORE UPDATE OF hosting_status_id ON hosting
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_name_from_id();

--------------------------------- end of backward compatibility ----------------------------
