DROP FUNCTION IF EXISTS get_permissions_for_data_element;

CREATE TABLE data_element_group (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);

INSERT INTO data_element_group (name, descr)
VALUES
    ('registrant', 'Data elements related to registrant contact'),
    ('admin', 'Data elements related to admin contact'),
    ('tech', 'Data elements related to tech contact'),
    ('billing', 'Data elements related to billing contact') ON CONFLICT DO NOTHING;

DROP VIEW IF EXISTS v_data_element;

ALTER TABLE IF EXISTS data_element DROP COLUMN IF EXISTS parent_id;
ALTER TABLE IF EXISTS data_element DROP COLUMN IF EXISTS tld_id;
ALTER TABLE IF EXISTS data_element DROP COLUMN IF EXISTS name;

ALTER TABLE IF EXISTS data_element ADD COLUMN IF NOT EXISTS name TEXT NOT NULL;
ALTER TABLE IF EXISTS data_element ADD COLUMN IF NOT EXISTS group_id UUID NOT NULL REFERENCES data_element_group;

CREATE INDEX ON data_element(group_id);
CREATE UNIQUE INDEX ON data_element(name, group_id);

INSERT INTO data_element (name, descr, group_id)
VALUES
    -- Registrant contact data elements
        ('first_name', 'First name of the registrant', tc_id_from_name('data_element_group', 'registrant')),
        ('last_name', 'Last name of the registrant', tc_id_from_name('data_element_group', 'registrant')),
        ('email', 'Email address of the registrant', tc_id_from_name('data_element_group', 'registrant')),
        ('address1', 'Primary address of the registrant', tc_id_from_name('data_element_group', 'registrant')),
        ('phone', 'Phone number of the registrant', tc_id_from_name('data_element_group', 'registrant')),

        -- Admin contact data elements
        ('first_name', 'First name of the admin contact', tc_id_from_name('data_element_group', 'admin')),
        ('last_name', 'Last name of the admin contact', tc_id_from_name('data_element_group', 'admin')),
        ('email', 'Email address of the admin contact', tc_id_from_name('data_element_group', 'admin')),
        ('address1', 'Primary address of the admin contact', tc_id_from_name('data_element_group', 'admin')),
        ('phone', 'Phone number of the admin contact', tc_id_from_name('data_element_group', 'admin')),

        -- Tech contact data elements
        ('first_name', 'First name of the tech contact', tc_id_from_name('data_element_group', 'tech')),
        ('last_name', 'Last name of the tech contact', tc_id_from_name('data_element_group', 'tech')),
        ('email', 'Email address of the tech contact', tc_id_from_name('data_element_group', 'tech')),
        ('address1', 'Primary address of the tech contact', tc_id_from_name('data_element_group', 'tech')),
        ('phone', 'Phone number of the tech contact', tc_id_from_name('data_element_group', 'tech')),

        -- Billing contact data elements
        ('first_name', 'First name of the billing contact', tc_id_from_name('data_element_group', 'billing')),
        ('last_name', 'Last name of the billing contact', tc_id_from_name('data_element_group', 'billing')),
        ('email', 'Email address of the billing contact', tc_id_from_name('data_element_group', 'billing')),
        ('address1', 'Primary address of the billing contact', tc_id_from_name('data_element_group', 'billing')),
        ('phone', 'Phone number of the billing contact', tc_id_from_name('data_element_group', 'billing')) ON CONFLICT DO NOTHING;

DROP TABLE IF EXISTS data_element_permission;

CREATE TABLE IF NOT EXISTS domain_data_element_permission (
    data_element_id     UUID NOT NULL REFERENCES data_element(id) ON DELETE CASCADE,
    permission_id       UUID NOT NULL REFERENCES permission(id),
    tld_id              UUID NOT NULL REFERENCES tld ON DELETE CASCADE,
    validity            TSTZRANGE NOT NULL DEFAULT (tstzrange(CURRENT_TIMESTAMP, 'infinity')),
    notes               TEXT,
    PRIMARY KEY (data_element_id, permission_id, validity)
) INHERITS (class.audit_trail);

CREATE UNIQUE INDEX ON domain_data_element_permission(data_element_id, permission_id, tld_id);


CREATE OR REPLACE FUNCTION upsert_domain_data_element_permission() RETURNS TRIGGER AS $$
BEGIN
    UPDATE domain_data_element_permission
    SET validity = NEW.validity,
        notes = NEW.notes
    WHERE data_element_id = NEW.data_element_id
      AND permission_id = NEW.permission_id
      AND tld_id = NEW.tld_id;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

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
            FROM domain_data_element_permission
            WHERE data_element_id = NEW.data_element_id AND tld_id = NEW.tld_id
            AND validity && NEW.validity
        ) THEN
            RAISE EXCEPTION 'Cannot insert must_not_collect as other permissions already exist for this data_element/tld';
        END IF;
    ELSE
        -- Ensure 'must_not_collect' is not already set for the same data_element in the same validity period
        IF EXISTS (
            SELECT 1
            FROM domain_data_element_permission dep
            JOIN permission p ON dep.permission_id = p.id
            WHERE dep.data_element_id = NEW.data_element_id AND dep.tld_id = NEW.tld_id
              AND p.name = 'must_not_collect'
              AND dep.validity && NEW.validity
        ) THEN
            RAISE EXCEPTION 'Cannot insert permission because must_not_collect is already set for this data_element/tld';
        END IF;

        -- Ensure at least one permission from the 'collection' group is set or being inserted for the validity period
        IF NOT EXISTS (
            SELECT 1
            FROM domain_data_element_permission dep
            JOIN permission p ON dep.permission_id = p.id
            JOIN permission_group pg ON p.group_id = pg.id
            WHERE dep.data_element_id = NEW.data_element_id AND dep.tld_id = NEW.tld_id
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

DROP TRIGGER IF EXISTS upsert_domain_data_element_permission_tg ON domain_data_element_permission;
CREATE TRIGGER upsert_domain_data_element_permission_tg
    BEFORE INSERT ON domain_data_element_permission
    FOR EACH ROW EXECUTE FUNCTION upsert_domain_data_element_permission();

DROP TRIGGER IF EXISTS  data_element_permission_insert_tg ON domain_data_element_permission;
CREATE TRIGGER data_element_permission_insert_tg
    BEFORE INSERT ON domain_data_element_permission
    FOR EACH ROW EXECUTE PROCEDURE data_element_permission_insert();


DROP VIEW IF EXISTS v_domain_data_element_permission;
CREATE OR REPLACE VIEW v_domain_data_element_permission AS
SELECT
    ddep.tld_id,
    ddep.created_date,
    ddep.updated_date,
    t.name AS tld_name,
    de.id as data_element_id,
    de.name as data_element_name,
    de.descr as data_element_descr,
    deg.id as data_element_group_id,
    deg.name as data_element_group,
    p.id as permission_id,
    p.name as permission_name,
    p.descr as permission_descr,
    pg.name as permission_group,
    LOWER(ddep.validity)::text as valid_from,
    UPPER(ddep.validity)::text as valid_to,
    ddep.notes
FROM domain_data_element_permission ddep
    LEFT JOIN data_element de ON de.id = ddep.data_element_id
    LEFT JOIN data_element_group deg ON deg.id = de.group_id
    LEFT JOIN permission p ON p.id = ddep.permission_id
    LEFT JOIN permission_group pg ON pg.id = p.group_id
    LEFT JOIN tld t ON t.id = ddep.tld_id
WHERE
    ddep.validity IS NULL
    OR (
        UPPER(ddep.validity) > CURRENT_TIMESTAMP
        AND
        LOWER(ddep.validity) <= CURRENT_TIMESTAMP
    );


CREATE OR REPLACE FUNCTION get_domain_data_elements_for_permission(
    p_tld_id UUID DEFAULT NULL,
    p_tld_name TEXT DEFAULT NULL,
    p_data_element_group_id UUID DEFAULT NULL,
    p_data_element_group TEXT DEFAULT NULL,
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

    IF p_data_element_group_id IS NULL AND p_data_element_group IS NULL THEN
        RAISE EXCEPTION 'Either p_data_element_group_id or p_data_element_group_name must be provided';
    END IF;

    IF p_permission_id IS NULL AND p_permission_name IS NULL THEN
        RAISE EXCEPTION 'Either p_permission_id or p_permission_name must be provided';
    END IF;

    SELECT ARRAY_AGG(vddep.data_element_name)
    INTO data_elements
    FROM v_domain_data_element_permission vddep
    WHERE (vddep.permission_name = p_permission_name OR vddep.permission_id = p_permission_id)
      AND (vddep.tld_id = p_tld_id OR vddep.tld_name = p_tld_name)
      AND (vddep.data_element_group_id = p_data_element_group_id OR vddep.data_element_group = p_data_element_group);

    RETURN data_elements;
END;
$$ LANGUAGE plpgsql;


