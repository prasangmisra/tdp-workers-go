-------------------------------------------------------------------------------stored_procedures.ddl-------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION data_element_permission_insert() RETURNS TRIGGER AS $$
BEGIN
    -- Validate that validity start date is not in the past
    IF LOWER(NEW.validity) < CURRENT_DATE THEN
        RAISE EXCEPTION 'Permission validity start date cannot be in the past';
    END IF;

    -- Check if the permission being inserted is 'must_not_collect'
    IF (SELECT name FROM permission WHERE id = NEW.permission_id) = 'must_not_collect' THEN
        -- Ensure no other permissions exist for the same data_element in the same validity period
        IF EXISTS (
            SELECT 1
            FROM data_element_permission
            WHERE data_element_id = NEW.data_element_id
              AND validity && NEW.validity
        ) THEN
            RAISE EXCEPTION 'Cannot insert must_not_collect as other permissions already exist for this data_element';
        END IF;
    ELSE
        -- Ensure 'must_not_collect' is not already set for the same data_element in the same validity period
        IF EXISTS (
            SELECT 1
            FROM data_element_permission dep
                     JOIN permission p ON dep.permission_id = p.id
            WHERE dep.data_element_id = NEW.data_element_id
              AND p.name = 'must_not_collect'
              AND dep.validity && NEW.validity
        ) THEN
            RAISE EXCEPTION 'Cannot insert permission because must_not_collect is already set for this data_element';
        END IF;

        -- Ensure at least one permission from the 'collection' group is set or being inserted for the validity period
        IF NOT EXISTS (
            SELECT 1
            FROM data_element_permission dep
                     JOIN permission p ON dep.permission_id = p.id
                     JOIN permission_group pg ON p.group_id = pg.id
            WHERE dep.data_element_id = NEW.data_element_id
              AND pg.name = 'collection'
              AND dep.validity && NEW.validity
        ) AND (
                  SELECT pg.name
                  FROM permission p
                           JOIN permission_group pg ON p.group_id = pg.id
                  WHERE p.id = NEW.permission_id
              ) != 'collection' THEN
            RAISE EXCEPTION 'At least one permission from the collection group must be set or inserted for this data_element';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------------------------------schema.ddl-------------------------------------------------------------------------------

--
-- table: permission_group
-- description: Groups that permission can be assigned to
--
CREATE TABLE permission_group(
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
                              parent_id   UUID REFERENCES data_element ON DELETE CASCADE,
                              tld_id      UUID NOT NULL REFERENCES tld ON DELETE CASCADE,
                              name        TEXT NOT NULL UNIQUE,
                              descr       TEXT
) INHERITS (class.audit_trail);

CREATE INDEX ON data_element(parent_id);

--
-- table: data_element_permission
-- description: Permissions assigned to data elements
--
CREATE TABLE data_element_permission (
                                         data_element_id UUID NOT NULL REFERENCES data_element(id) ON DELETE CASCADE,
                                         permission_id   UUID NOT NULL REFERENCES permission(id),
                                         validity        TSTZRANGE NOT NULL DEFAULT '(-Infinity,Infinity)',
                                         PRIMARY KEY (data_element_id, permission_id, validity)
);

CREATE TRIGGER data_element_permission_insert_tg
    BEFORE INSERT ON data_element_permission
    FOR EACH ROW EXECUTE PROCEDURE data_element_permission_insert();

-------------------------------------------------------------------------------views.ddl-------------------------------------------------------------------------------

--
-- view: v_data_elements
-- description: This view aggregates data elements and their associated permissions into a JSONB array.
--
DROP VIEW IF EXISTS v_data_element;
CREATE OR REPLACE VIEW v_data_element AS
SELECT
    de.id,
    de.parent_id,
    t.name AS tld,
    de.name,
    de.descr,
    p.id as permission_id,
    p.name as permission_name,
    pg.name as permission_group,
    p.descr as permission_descr,
    LOWER(dep.validity)::text as validity_from,
    UPPER(dep.validity)::text as validity_to
FROM data_element de
         LEFT JOIN data_element_permission dep ON de.id = dep.data_element_id
         LEFT JOIN permission p ON p.id = dep.permission_id
         LEFT JOIN permission_group pg ON pg.id = p.group_id
         LEFT JOIN tld t ON t.id = de.tld_id
WHERE
    dep.validity IS NULL OR UPPER(dep.validity) > CURRENT_DATE;


-------------------------------------------------------------------------------functions.ddl-------------------------------------------------------------------------------

--
-- function: get_permissions_for_data_element
-- description: This function returns the permissions for a data element and its children
--              for a given permission group.
--
CREATE OR REPLACE FUNCTION get_permissions_for_data_element(p_data_element_name TEXT, p_permission_group_name TEXT)
    RETURNS TABLE (
                      data_element_name TEXT,
                      permission_id UUID,
                      permission_name TEXT,
                      group_name TEXT,
                      descr TEXT
                  ) AS $$
BEGIN
    -- Check if the data element exists
    IF NOT EXISTS (SELECT 1 FROM data_element de WHERE de.name = p_data_element_name) THEN
        RAISE EXCEPTION 'Data element with ID % does not exist', p_data_element_name;
    END IF;

    -- Check if the permission group exists
    IF NOT EXISTS (SELECT 1 FROM permission_group pg WHERE pg.name = p_permission_group_name) THEN
        RAISE EXCEPTION 'Permission group with ID % does not exist', p_permission_group_name;
    END IF;

    -- Return the permissions for the data element and its children
    RETURN QUERY
        WITH RECURSIVE element_tree AS (
            SELECT de.id, de.name
            FROM data_element de
            WHERE de.name = p_data_element_name

            UNION ALL

            SELECT de.id, de.name
            FROM data_element de
                     JOIN element_tree et ON de.parent_id = et.id
        )
        SELECT
            et.name AS data_element_name,
            p.id AS permission_id,
            p.name AS permission_name,
            pg.name AS group_name,
            p.descr AS description
        FROM data_element_permission dep
                 JOIN permission p ON dep.permission_id = p.id
                 JOIN permission_group pg ON p.group_id = pg.id
                 JOIN element_tree et ON dep.data_element_id = et.id
        WHERE pg.name = p_permission_group_name;
END;
$$ LANGUAGE plpgsql;
