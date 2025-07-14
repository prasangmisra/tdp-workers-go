CREATE TABLE attr_category(
    id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    descr       TEXT,
    parent_id   UUID REFERENCES attr_category(id)
);
CREATE INDEX ON attr_category(parent_id);

CREATE TABLE attr_value_type(
    id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    data_type   REGTYPE NOT NULL
);

CREATE TABLE attr_key(
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name            TEXT NOT NULL,
    category_id     UUID NOT NULL REFERENCES attr_category,
    descr           TEXT,
    value_type_id   UUID NOT NULL REFERENCES attr_value_type,
    default_value   TEXT,
    allow_null      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX ON attr_key(category_id);
CREATE INDEX ON attr_key(value_type_id);

ALTER TABLE attr_key
ADD CONSTRAINT unique_attr_key_unique_name_and_category_id
UNIQUE (name,category_id);

CREATE TABLE attr_value(
    id                   UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id            UUID NOT NULL REFERENCES tenant,
    key_id               UUID NOT NULL REFERENCES attr_key ON DELETE CASCADE,
    tld_id               UUID REFERENCES tld ON DELETE CASCADE,
    provider_instance_id UUID REFERENCES provider_instance ON DELETE CASCADE,
    provider_id          UUID REFERENCES provider ON DELETE CASCADE,
    registry_id          UUID REFERENCES registry ON DELETE CASCADE,
    value_integer        INTEGER,
    value_text           TEXT,
    value_integer_range  INT4RANGE,
    value_daterange      DATERANGE,
    value_tstzrange      TSTZRANGE,
    value_boolean        BOOL,
    value_text_list      TEXT[],
    value_integer_list   INT[],
    value_regex          REGEX,
    value_percentage     PERCENTAGE,
    CHECK(
        (
            (tld_id IS NOT NULL)::INTEGER +
            (provider_instance_id IS NOT NULL)::INTEGER +
            (provider_id IS NOT NULL)::INTEGER +
            (registry_id IS NOT NULL)::INTEGER
        ) IN (0,1)
    ),
    CHECK(
        (
            (value_integer IS NOT NULL )::INTEGER +      
            (value_text IS NOT NULL )::INTEGER +         
            (value_integer_range IS NOT NULL )::INTEGER +
            (value_boolean IS NOT NULL )::INTEGER +      
            (value_text_list IS NOT NULL )::INTEGER +    
            (value_daterange IS NOT NULL )::INTEGER +
            (value_tstzrange IS NOT NULL )::INTEGER +
            (value_integer_list IS NOT NULL )::INTEGER +
            (value_regex IS NOT NULL )::INTEGER +
            (value_percentage IS NOT NULL )::INTEGER
        ) = 1
    ),
    UNIQUE(key_id,tld_id,tenant_id),
    UNIQUE(key_id,provider_instance_id),
    UNIQUE(key_id,provider_id),
    UNIQUE(key_id,registry_id)
);
CREATE UNIQUE INDEX ON attr_value(key_id) WHERE COALESCE(tld_id,provider_instance_id,provider_id,registry_id) IS NULL;

CREATE TRIGGER attr_value_insert_tg BEFORE INSERT ON attr_value 
    FOR EACH ROW EXECUTE PROCEDURE attr_value_insert();

-- Hierarchy for configuration is:
--   1. tld
--   2. provider_instance
--   3. provider
--   4. registry
--   5. default value
--
-- This means that the orders will be prioritized based on whether
-- there is a setting written in that order and will fall back to 
-- the default value.
