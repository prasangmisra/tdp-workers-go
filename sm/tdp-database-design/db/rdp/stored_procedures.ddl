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
