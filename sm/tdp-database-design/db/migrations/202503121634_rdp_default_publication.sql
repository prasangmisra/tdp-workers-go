INSERT INTO permission_group (name, descr)
VALUES
    ('publication', 'Permissions related to publication to RDDS')
ON CONFLICT DO NOTHING;

INSERT INTO permission (name, descr, group_id)
VALUES
    ('publish_by_default', 'Data element will be published in RDDS', tc_id_from_name('permission_group', 'publication'))
ON CONFLICT DO NOTHING;

UPDATE permission
SET group_id = tc_id_from_name('permission_group', 'publication')
WHERE name = 'available_for_consent';

DELETE FROM permission_group WHERE name = 'consent';

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

        -- Ensure available_for_consent and publish_by_default are not inserted if the other already exists for the same data_element in the same validity period
        IF EXISTS (
            SELECT 1
            FROM domain_data_element_permission ddep
            JOIN permission p ON ddep.permission_id = p.id
            WHERE ddep.domain_data_element_id = NEW.domain_data_element_id
              AND ddep.validity && NEW.validity
              AND (
              (p.name = 'publish_by_default' AND (
                  SELECT p2.name
                  FROM permission p2
                  WHERE p2.id = NEW.permission_id
              ) = 'available_for_consent')
              OR
              (p.name = 'available_for_consent' AND (
                  SELECT p2.name
                  FROM permission p2
                  WHERE p2.id = NEW.permission_id
              ) = 'publish_by_default')
              )
        ) THEN
            RAISE EXCEPTION 'Cannot insert permission as available_for_consent and publish_by_default are mutually exclusive';
        END IF;

    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP VIEW IF EXISTS v_rdp_data_element;
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
            jsonb_object_agg(permission_name, true) FILTER (WHERE permission_group = 'publication'),
            '{}'::jsonb
        ) AS publication
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
            WHERE group_id = tc_id_from_name('permission_group' ,'publication')
        ) || publication
    END AS publication
FROM rdp_data_element;
