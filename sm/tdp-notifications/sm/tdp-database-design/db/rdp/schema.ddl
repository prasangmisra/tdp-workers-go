--
-- table: permission_group
-- description: Groups that permission can be assigned to
--
CREATE TABLE permission_group (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);

--
-- table: permission
-- description: Permissions that can be assigned to data elements
--
CREATE TABLE permission (
    id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    descr       TEXT,
    group_id    UUID NOT NULL REFERENCES permission_group
) INHERITS (class.audit_trail);

CREATE INDEX ON permission(group_id);
CREATE UNIQUE INDEX ON permission(name, group_id);

--
-- table: data_element
-- description: Data elements to which permissions can be assigned
--
CREATE TABLE data_element (
    id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL,
    descr       TEXT,
    parent_id   UUID REFERENCES data_element ON DELETE CASCADE
) INHERITS (class.audit_trail);

CREATE INDEX ON data_element(parent_id);

-- Create a unique constraint for parent_id+name combination
CREATE UNIQUE INDEX data_element_parent_name_unique
    ON data_element (parent_id, name)
    WHERE parent_id IS NOT NULL;

-- Create a unique constraint for global data elements (where parent_id is null)
CREATE UNIQUE INDEX data_element_global_name_unique
    ON data_element(name)
    WHERE parent_id IS NULL;

--
-- table: data_element
-- description: Data elements to which permissions can be assigned
--
CREATE TABLE domain_data_element (
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    data_element_id     UUID NOT NULL REFERENCES data_element(id) ON DELETE CASCADE,
    tld_id              UUID NOT NULL REFERENCES tld ON DELETE CASCADE
) INHERITS (class.audit_trail);

CREATE INDEX ON domain_data_element(tld_id);
CREATE INDEX ON domain_data_element(data_element_id);
CREATE UNIQUE INDEX ON domain_data_element(data_element_id, tld_id);

--
-- table: domain_data_element_permission
-- description: Permissions assigned to domain related data elements
--
CREATE TABLE domain_data_element_permission (
    domain_data_element_id  UUID NOT NULL REFERENCES domain_data_element(id) ON DELETE CASCADE,
    permission_id           UUID NOT NULL REFERENCES permission(id),
    validity                TSTZRANGE NOT NULL DEFAULT (tstzrange(CURRENT_TIMESTAMP, 'infinity')),
    notes                   TEXT,
    PRIMARY KEY (domain_data_element_id, permission_id, validity)
) INHERITS (class.audit_trail);

CREATE UNIQUE INDEX ON domain_data_element_permission(domain_data_element_id, permission_id);

CREATE TRIGGER upsert_domain_data_element_permission_tg
    BEFORE INSERT ON domain_data_element_permission
    FOR EACH ROW EXECUTE FUNCTION upsert_domain_data_element_permission();

CREATE TRIGGER domain_data_element_permission_insert_tg
    BEFORE INSERT ON domain_data_element_permission
    FOR EACH ROW EXECUTE PROCEDURE domain_data_element_permission_insert();

CREATE TRIGGER set_domain_data_element_updated_date_tg
    AFTER INSERT OR UPDATE OR DELETE ON domain_data_element_permission
    FOR EACH ROW EXECUTE FUNCTION set_domain_data_element_updated_date();
