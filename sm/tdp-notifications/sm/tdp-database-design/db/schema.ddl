CREATE SCHEMA IF NOT EXISTS class;

CREATE TABLE class.audit (
  created_date          TIMESTAMPTZ DEFAULT NOW(),
  updated_date          TIMESTAMPTZ,
  created_by            TEXT DEFAULT CURRENT_USER,
  updated_by            TEXT
);

CREATE TABLE class.audit_trail (
) INHERITS (class.audit);


CREATE TABLE class.soft_delete (
  deleted_date          TIMESTAMPTZ,
  deleted_by            TEXT
);

--
-- Trail of changes made to tables that inherit from _audit.
--
CREATE TABLE audit_trail_log (
  id              BIGSERIAL NOT NULL,
  table_name      TEXT NOT NULL,
  operation       TEXT CHECK ( operation = 'INSERT'
                         OR operation = 'TRUNCATE'
                         OR operation = 'UPDATE'
                         OR operation = 'DELETE' ),
  object_id       UUID,
  old_value       HSTORE,
  new_value       HSTORE,
  statement_date  TIMESTAMPTZ DEFAULT CLOCK_TIMESTAMP(),
  created_date    TIMESTAMPTZ DEFAULT NOW(),
  updated_date    TIMESTAMPTZ,
  created_by      TEXT DEFAULT CURRENT_USER,
  updated_by      TEXT,
  PRIMARY KEY ( id, created_date )
) PARTITION BY RANGE (created_date);


COMMENT ON TABLE audit_trail_log IS '
Record of changes made to tables that inherit from _audit.
Note: Only stored for relations that have an "id" primary index.
';

COMMENT ON COLUMN audit_trail_log.table_name IS '
`type` stores the name of the table that was affected by the current
operation.
';

COMMENT ON COLUMN audit_trail_log.operation IS '
Stores the type of SQL operation performed and must be one of
`INSERT`, `TRUNCATE`, `UPDATE` or `DELETE`.

Depending on the actual value of this column, `old_value` and
`new_value` might be `NULL` (ie, there''s no `new_value` for a
`DELETE` operation).
';

COMMENT ON COLUMN audit_trail_log.old_value IS '
Contain data encoded with `hstore`, representing the state of the
affected row before the `operation` was performed. This is stored as
simple text and must be converted back to `hstore` when data is to be
extracted within the database.
';

COMMENT ON COLUMN audit_trail_log.new_value IS '
Contain data encoded with `hstore`, representing the state of the
affected row after the `operation` was performed. This is stored as
simple text and must be converted back to `hstore` when data is to be
extracted within the database.
';

SELECT partition_helper_by_month('audit_trail_log');



--
-- Manage schema migrations.
--
CREATE TABLE migration (
    version             TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    version_number      TEXT NOT NULL,
    applied_date        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT valid_version_format CHECK (version_number ~ '^v[0-9]+\.[0-9]+\.[0-9]+$')
);

COMMENT ON TABLE migration IS '
Record of schema migrations applied.
';

COMMENT ON COLUMN migration.version      IS 'Timestamp string of migration file in format YYYYMMDDHHMMSS (must match filename).';
COMMENT ON COLUMN migration.name         IS 'Name of migration from migration filename.';
COMMENT ON COLUMN migration.applied_date IS 'Postgres timestamp when migration was recorded.';


--
-- table: country
-- description: this table lists all known countries
--

CREATE TABLE country (
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name         TEXT NOT NULL,
  alpha2       TEXT NOT NULL CHECK(LENGTH(alpha2) = 2),
  alpha3       TEXT NOT NULL CHECK(LENGTH(alpha3) = 3),
  calling_code TEXT,  
  UNIQUE(name),
  UNIQUE(alpha2),
  UNIQUE(alpha3)
);

COMMENT ON COLUMN country.name IS         'The country''s name.';
COMMENT ON COLUMN country.alpha2 IS       'The ISO 3166-1 two letter country code, see https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2.';
COMMENT ON COLUMN country.alpha3 IS       'The ISO 3166-1 three letter country code, see https://en.wikipedia.org/wiki/ISO_3166-1_alpha-3.';
COMMENT ON COLUMN country.calling_code IS 'The country''s calling code accord, see https://en.wikipedia.org/wiki/List_of_country_calling_codes.';


--
-- table: language
-- description: this table lists all known languages
--

CREATE TABLE language (
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name         TEXT NOT NULL,
  alpha2       TEXT NOT NULL CHECK(LENGTH(alpha2) = 2),
  alpha3t      TEXT NOT NULL CHECK(LENGTH(alpha3t) = 3),
  alpha3b      TEXT NOT NULL CHECK(LENGTH(alpha3b) = 3),
  UNIQUE(name),
  UNIQUE(alpha2),
  UNIQUE(alpha3t),
  UNIQUE(alpha3b)
);

COMMENT ON COLUMN language.name IS        'The language''s name.';
COMMENT ON COLUMN language.alpha2 IS      'The ISO 639-1 two letter language code, see https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes.';
COMMENT ON COLUMN language.alpha3t IS     'The ISO 639-2/T three letter language code, see https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes.';
COMMENT ON COLUMN language.alpha3b IS     'The ISO 639-2/B three letter language code, see https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes.';


CREATE TABLE attribute_type (
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name         TEXT NOT NULL UNIQUE,
  descr        TEXT
) INHERITS (class.audit);;

--
-- table: attribute
-- description: lists attributes, possibly in a hierarchy, to be stored in a *_attribute_* table
--


-- TODO: write a check constraint that if parent is set, the child type is the same as parent
CREATE TABLE attribute(
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  type_id      UUID NOT NULL REFERENCES attribute_type ON DELETE CASCADE,
  name         TEXT NOT NULL,
  descr        TEXT NOT NULL,
  parent_id    UUID REFERENCES attribute,
  filter       TEXT,
  UNIQUE(type_id,name),
  UNIQUE(type_id,id)
);

COMMENT ON COLUMN attribute.name IS        'The attributes''s name.';
COMMENT ON COLUMN attribute.type_id IS      'The type of attribute from the attribute_type table';
COMMENT ON COLUMN attribute.descr IS       'A description of the attribute.';
COMMENT ON COLUMN attribute.parent_id IS   'Reference to build a hierarchy of attributes.';
COMMENT On COLUMN attribute.filter IS       $string$A SELECT query to filter the attribute''s value, like $$SELECT alpha2 FROM country WHERE alpha2=trim('%s')$$.$string$;

--
-- table: currency_type
-- description: this table lists all known currencies
--

CREATE TABLE currency_type (
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name         TEXT NOT NULL UNIQUE,
  descr        TEXT,
  fraction     INT NOT NULL DEFAULT 1
) INHERITS (class.audit);
