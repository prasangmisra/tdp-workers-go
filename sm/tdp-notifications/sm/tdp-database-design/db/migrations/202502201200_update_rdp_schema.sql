DROP FUNCTION IF EXISTS get_domain_data_elements_for_permission;
CREATE OR REPLACE FUNCTION get_domain_data_elements_for_permission(
    p_tld_id UUID DEFAULT NULL,
    p_tld_name TEXT DEFAULT NULL,
    p_data_element_parent_id UUID DEFAULT NULL,
    p_data_element_parent_name TEXT DEFAULT NULL,
    p_permission_id UUID DEFAULT NULL,
    p_permission_name TEXT DEFAULT NULL
) 
RETURNS TEXT[] AS $$
DECLARE
    data_elements TEXT[];
BEGIN
    IF p_tld_id IS NULL AND p_tld_name IS NULL THEN
        RAISE EXCEPTION 'Either p_tld_id or p_tld_name must be provided';
    END IF;

    IF p_data_element_parent_id IS NULL AND p_data_element_parent_name IS NULL THEN
        RAISE EXCEPTION 'Either p_data_element_parent_id or p_data_element_parent_name must be provided';
    END IF;

    IF p_permission_id IS NULL AND p_permission_name IS NULL THEN
        RAISE EXCEPTION 'Either p_permission_id or p_permission_name must be provided';
    END IF;

    SELECT ARRAY_AGG(vddep.data_element_name)
    INTO data_elements
    FROM v_domain_data_element_permission vddep
    WHERE (vddep.permission_name = p_permission_name OR vddep.permission_id = p_permission_id)
      AND (vddep.tld_id = p_tld_id OR vddep.tld_name = p_tld_name)
      AND (vddep.data_element_parent_id = p_data_element_parent_id OR vddep.data_element_parent_name = p_data_element_parent_name);
   
    RETURN data_elements;
END;
$$ LANGUAGE plpgsql;

-- drop all data first
TRUNCATE data_element CASCADE;

DROP VIEW IF EXISTS v_domain_data_element_permission;

ALTER TABLE IF EXISTS data_element DROP COLUMN IF EXISTS group_id;
ALTER TABLE IF EXISTS data_element ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES data_element ON DELETE CASCADE;

CREATE INDEX ON data_element(parent_id);

DROP TABLE IF EXISTS data_element_group;

-- Create a unique constraint for parent_id+name combination
CREATE UNIQUE INDEX IF NOT EXISTS data_element_parent_name_unique
    ON data_element (parent_id, name)
    WHERE parent_id IS NOT NULL;

-- Create a unique constraint for global data elements (where parent_id is null)
CREATE UNIQUE INDEX IF NOT EXISTS data_element_global_name_unique
    ON data_element(name)
    WHERE parent_id IS NULL;


WITH registrant_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('registrant', 'Data element related to registrant contact')
    RETURNING id
), admin_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('admin', 'Data element related to admin contact')
    RETURNING id
), tech_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('tech', 'Data element related to tech contact')
    RETURNING id
), billing_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('billing', 'Data element related to billing contact')
    RETURNING id
)
INSERT INTO data_element (name, descr, parent_id)
VALUES
    -- Registrant contact data elements
    ('first_name', 'First name of the registrant', (SELECT id FROM registrant_de)),
    ('last_name', 'Last name of the registrant', (SELECT id FROM registrant_de)),
    ('email', 'Email address of the registrant', (SELECT id FROM registrant_de)),
    ('address1', 'Primary address of the registrant', (SELECT id FROM registrant_de)),
    ('phone', 'Phone number of the registrant', (SELECT id FROM registrant_de)),
    ('org_name', 'Name of the registrant organization', (SELECT id FROM registrant_de)),
    ('address2', 'Secondary address of the registrant', (SELECT id FROM registrant_de)),
    ('address3', 'Tertiary address of the registrant', (SELECT id FROM registrant_de)),
    ('city', 'City of the registrant', (SELECT id FROM registrant_de)),
    ('state', 'State of the registrant', (SELECT id FROM registrant_de)),
    ('postal_code', 'Postal code of the registrant', (SELECT id FROM registrant_de)),
    ('country', 'Country of the registrant', (SELECT id FROM registrant_de)),
    ('fax', 'Fax number of the registrant', (SELECT id FROM registrant_de)),
    ('pw', 'Password of the registrant', (SELECT id FROM registrant_de)),

    -- Admin contact data elements
    ('first_name', 'First name of the admin contact', (SELECT id FROM admin_de)),
    ('last_name', 'Last name of the admin contact', (SELECT id FROM admin_de)),
    ('email', 'Email address of the admin contact', (SELECT id FROM admin_de)),
    ('address1', 'Primary address of the admin contact', (SELECT id FROM admin_de)),
    ('phone', 'Phone number of the admin contact', (SELECT id FROM admin_de)),
    ('org_name', 'Name of the admin organization', (SELECT id FROM admin_de)),
    ('address2', 'Secondary address of the admin contact', (SELECT id FROM admin_de)),
    ('address3', 'Tertiary address of the admin contact', (SELECT id FROM admin_de)),
    ('city', 'City of the admin contact', (SELECT id FROM admin_de)),
    ('state', 'State of the admin contact', (SELECT id FROM admin_de)),
    ('postal_code', 'Postal code of the admin contact', (SELECT id FROM admin_de)),
    ('country', 'Country of the admin contact', (SELECT id FROM admin_de)),
    ('fax', 'Fax number of the admin contact', (SELECT id FROM admin_de)),
    ('pw', 'Password of the admin contact', (SELECT id FROM admin_de)),

    -- Tech contact data elements
    ('first_name', 'First name of the tech contact', (SELECT id FROM tech_de)),
    ('last_name', 'Last name of the tech contact', (SELECT id FROM tech_de)),
    ('email', 'Email address of the tech contact', (SELECT id FROM tech_de)),
    ('address1', 'Primary address of the tech contact', (SELECT id FROM tech_de)),
    ('phone', 'Phone number of the tech contact', (SELECT id FROM tech_de)),
    ('org_name', 'Name of the tech organization', (SELECT id FROM tech_de)),
    ('address2', 'Secondary address of the tech contact', (SELECT id FROM tech_de)),
    ('address3', 'Tertiary address of the tech contact', (SELECT id FROM tech_de)),
    ('city', 'City of the tech contact', (SELECT id FROM tech_de)),
    ('state', 'State of the tech contact', (SELECT id FROM tech_de)),
    ('postal_code', 'Postal code of the tech contact', (SELECT id FROM tech_de)),
    ('country', 'Country of the tech contact', (SELECT id FROM tech_de)),
    ('fax', 'Fax number of the tech contact', (SELECT id FROM tech_de)),
    ('pw', 'Password of the tech contact', (SELECT id FROM tech_de)),

    -- Billing contact data elements
    ('first_name', 'First name of the billing contact', (SELECT id FROM billing_de)),
    ('last_name', 'Last name of the billing contact', (SELECT id FROM billing_de)),
    ('email', 'Email address of the billing contact', (SELECT id FROM billing_de)),
    ('address1', 'Primary address of the billing contact', (SELECT id FROM billing_de)),
    ('phone', 'Phone number of the billing contact', (SELECT id FROM billing_de)),
    ('org_name', 'Name of the billing organization', (SELECT id FROM billing_de)),
    ('address2', 'Secondary address of the billing contact', (SELECT id FROM billing_de)),
    ('address3', 'Tertiary address of the billing contact', (SELECT id FROM billing_de)),
    ('city', 'City of the billing contact', (SELECT id FROM billing_de)),
    ('state', 'State of the billing contact', (SELECT id FROM billing_de)),
    ('postal_code', 'Postal code of the billing contact', (SELECT id FROM billing_de)),
    ('country', 'Country of the billing contact', (SELECT id FROM billing_de)),
    ('fax', 'Fax number of the billing contact', (SELECT id FROM billing_de)),
    ('pw', 'Password of the billing contact', (SELECT id FROM billing_de))
ON CONFLICT DO NOTHING;


CREATE TABLE IF NOT EXISTS domain_data_element (
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    data_element_id     UUID NOT NULL REFERENCES data_element(id) ON DELETE CASCADE,
    tld_id              UUID NOT NULL REFERENCES tld ON DELETE CASCADE
) INHERITS (class.audit_trail);

CREATE INDEX ON domain_data_element(tld_id);
CREATE INDEX ON domain_data_element(data_element_id);

CREATE UNIQUE INDEX ON domain_data_element(data_element_id, tld_id);

DROP TABLE IF EXISTS domain_data_element_permission;
CREATE TABLE domain_data_element_permission (
    domain_data_element_id  UUID NOT NULL REFERENCES domain_data_element(id) ON DELETE CASCADE,
    permission_id           UUID NOT NULL REFERENCES permission(id),
    validity                TSTZRANGE NOT NULL DEFAULT (tstzrange(CURRENT_TIMESTAMP, 'infinity')),
    notes                   TEXT,
    PRIMARY KEY (domain_data_element_id, permission_id, validity)
) INHERITS (class.audit_trail);

CREATE UNIQUE INDEX ON domain_data_element_permission(domain_data_element_id, permission_id);

-- function: upsert_domain_data_element_permission()
-- description: updates validity and notes for existing records, inserts new records if they do not exist

CREATE OR REPLACE FUNCTION upsert_domain_data_element_permission() RETURNS TRIGGER AS $$
BEGIN
    UPDATE domain_data_element_permission
    SET validity = NEW.validity,
        notes = NEW.notes
    WHERE domain_data_element_id = NEW.domain_data_element_id
      AND permission_id = NEW.permission_id;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- set updated date for the related domain data element
    UPDATE domain_data_element
    SET updated_date = CURRENT_TIMESTAMP
    WHERE id = NEW.domain_data_element_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- function: set_domain_data_element_updated_date()
-- description: updates updated_date on related domain data element when a new permission is inserted updated

CREATE OR REPLACE FUNCTION set_domain_data_element_updated_date() RETURNS TRIGGER AS $$
BEGIN

    -- set updated date for the related domain data element
    UPDATE domain_data_element
    SET updated_date = CURRENT_TIMESTAMP
    WHERE id = NEW.domain_data_element_id OR id = OLD.domain_data_element_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS data_element_permission_insert;

-- function: data_element_permission_insert()
-- description: This function validates the data_element_permission table before inserting a new record.
CREATE OR REPLACE FUNCTION domain_data_element_permission_insert() RETURNS TRIGGER AS $$
BEGIN
    -- Validate that validity start date is not in the past
    IF LOWER(NEW.validity) < CURRENT_DATE THEN
        RAISE EXCEPTION 'Permission validity start date cannot be in the past';
    END IF;

    -- Check if the permission being inserted is 'must_not_collect'
    IF tc_name_from_id('permission', NEW.permission_id) = 'must_not_collect' THEN
        -- Ensure no other permissions exist for the same data_element in the same validity period
        IF EXISTS (
            SELECT 1
            FROM domain_data_element_permission
            WHERE domain_data_element_id = NEW.domain_data_element_id
            AND validity && NEW.validity
        ) THEN
            RAISE EXCEPTION 'Cannot insert must_not_collect as other permissions already exist for this data_element/tld';
        END IF;
    ELSE
        -- Ensure 'must_not_collect' is not already set for the same data_element in the same validity period
        IF EXISTS (
            SELECT 1
            FROM domain_data_element_permission ddep
            JOIN permission p ON ddep.permission_id = p.id
            WHERE ddep.domain_data_element_id = NEW.domain_data_element_id
              AND p.name = 'must_not_collect'
              AND ddep.validity && NEW.validity
        ) THEN
            RAISE EXCEPTION 'Cannot insert permission because must_not_collect is already set for this data_element/tld';
        END IF;

        -- Ensure at least one permission from the 'collection' group is set or being inserted for the validity period
        IF NOT EXISTS (
            SELECT 1
            FROM domain_data_element_permission ddep
            JOIN permission p ON ddep.permission_id = p.id
            JOIN permission_group pg ON p.group_id = pg.id
            WHERE ddep.domain_data_element_id = NEW.domain_data_element_id
              AND pg.name = 'collection'
              AND ddep.validity && NEW.validity
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


DROP TRIGGER IF EXISTS upsert_domain_data_element_permission_tg ON domain_data_element_permission;
CREATE TRIGGER upsert_domain_data_element_permission_tg
    BEFORE INSERT ON domain_data_element_permission
    FOR EACH ROW EXECUTE FUNCTION upsert_domain_data_element_permission();

DROP TRIGGER IF EXISTS domain_data_element_permission_insert_tg ON domain_data_element_permission;
CREATE TRIGGER domain_data_element_permission_insert_tg
    BEFORE INSERT ON domain_data_element_permission
    FOR EACH ROW EXECUTE PROCEDURE domain_data_element_permission_insert();

DROP TRIGGER IF EXISTS set_domain_data_element_updated_date_tg ON domain_data_element_permission;
CREATE TRIGGER set_domain_data_element_updated_date_tg
    AFTER INSERT OR UPDATE OR DELETE ON domain_data_element_permission
    FOR EACH ROW EXECUTE FUNCTION set_domain_data_element_updated_date();

DROP VIEW IF EXISTS v_data_element;
CREATE OR REPLACE VIEW v_data_element AS 
WITH RECURSIVE element AS (
    SELECT id, NULL::UUID AS parent_id, NULL AS parent_name, name, name AS full_name, descr FROM data_element WHERE parent_id IS NULL
    UNION 
    SELECT c.id, p.id AS parent_id, p.name AS parent_name, c.name, p.name || '.' || c.name AS full_name, c.descr FROM data_element c 
    JOIN element p ON p.id = c.parent_id 
)
SELECT * FROM element;

CREATE OR REPLACE VIEW v_domain_data_element_permission AS
SELECT
    dde.created_date,
    dde.updated_date,
    dde.tld_id,
    t.name AS tld_name,
    dde.id as domain_data_element_id,
    vde.id as data_element_id,
    vde.parent_id as data_element_parent_id,
    vde.parent_name as data_element_parent_name,
    vde.name as data_element_name,
    vde.full_name as data_element_full_name,
    vde.descr as data_element_descr,
    p.id as permission_id,
    p.name as permission_name,
    p.descr as permission_descr,
    pg.name as permission_group,
    LOWER(ddep.validity)::text as valid_from,
    UPPER(ddep.validity)::text as valid_to,
    ddep.notes
FROM domain_data_element_permission ddep
    JOIN domain_data_element dde ON dde.id = ddep.domain_data_element_id
    JOIN v_data_element vde ON vde.id = dde.data_element_id
    JOIN permission p ON p.id = ddep.permission_id
    JOIN permission_group pg ON p.group_id = pg.id
    JOIN tld t ON t.id = dde.tld_id
WHERE
    ddep.validity IS NULL
    OR (
        UPPER(ddep.validity) > CURRENT_TIMESTAMP
        AND
        LOWER(ddep.validity) <= CURRENT_TIMESTAMP
    );

CREATE OR REPLACE VIEW v_rdp_data_element AS
WITH rdp_data_element AS (
    SELECT
        created_date,
        updated_date,
        tld_name as tld,
        data_element_parent_name as group,
        data_element_name as property,
        (array_agg(permission_name) FILTER (WHERE permission_group = 'collection'))[1] as collection,
        COALESCE(
            jsonb_object_agg(permission_name, true) FILTER (WHERE permission_group = 'transmission'),
            '{}'::jsonb
        ) AS transmission,
        COALESCE(
            jsonb_object_agg(permission_name, true) FILTER (WHERE permission_group = 'consent'),
            '{}'::jsonb
        ) AS consent
    FROM v_domain_data_element_permission
    GROUP BY
        created_date,
        updated_date,
        tld_name,
        data_element_parent_name,
        data_element_name,
        domain_data_element_id
)
SELECT
    created_date,
    updated_date,
    tld,
    "group",
    property,
    collection,
    CASE
        WHEN collection = 'must_not_collect' THEN NULL
        ELSE (
            SELECT jsonb_object_agg(name, false)
            FROM permission
            WHERE group_id = tc_id_from_name('permission_group' ,'transmission')
        ) || transmission
    END AS transmission,
    CASE
        WHEN collection = 'must_not_collect' THEN NULL
        ELSE (
            SELECT jsonb_object_agg(name, false)
            FROM permission
            WHERE group_id = tc_id_from_name('permission_group' ,'consent')
        ) || consent
    END AS consent
FROM rdp_data_element;
