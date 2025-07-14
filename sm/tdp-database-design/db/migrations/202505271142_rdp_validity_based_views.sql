DROP VIEW IF EXISTS v_rdp_data_element;

DROP VIEW IF EXISTS v_domain_data_element_permission;
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
    ddep.notes,
    ddep.validity
FROM domain_data_element_permission ddep
         JOIN domain_data_element dde ON dde.id = ddep.domain_data_element_id
         JOIN v_data_element vde ON vde.id = dde.data_element_id
         JOIN permission p ON p.id = ddep.permission_id
         JOIN permission_group pg ON p.group_id = pg.id
         JOIN tld t ON t.id = dde.tld_id;

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
                 WHERE group_id = tc_id_from_name('permission_group', 'transmission')
             ) || transmission
        END AS transmission,
    CASE
        WHEN collection = 'must_not_collect' THEN NULL
        ELSE (
                 SELECT jsonb_object_agg(name, false)
                 FROM permission
                 WHERE group_id = tc_id_from_name('permission_group', 'publication')
             ) || publication
        END AS publication
FROM rdp_data_element
WHERE collection IS NOT NULL;

DROP VIEW IF EXISTS v_valid_rdp_data_element;
CREATE OR REPLACE VIEW v_valid_rdp_data_element AS
WITH valid_rdp_data_element AS (
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
    WHERE
        validity IS NULL
       OR (
        UPPER(validity) > CURRENT_TIMESTAMP
            AND
        LOWER(validity) <= CURRENT_TIMESTAMP
        )
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
                 WHERE group_id = tc_id_from_name('permission_group', 'transmission')
             ) || transmission
        END AS transmission,
    CASE
        WHEN collection = 'must_not_collect' THEN NULL
        ELSE (
                 SELECT jsonb_object_agg(name, false)
                 FROM permission
                 WHERE group_id = tc_id_from_name('permission_group', 'publication')
             ) || publication
        END AS publication
FROM valid_rdp_data_element
WHERE collection IS NOT NULL;


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
      AND (vddep.data_element_parent_id = p_data_element_parent_id OR vddep.data_element_parent_name = p_data_element_parent_name)
      AND (
        vddep.validity IS NULL
            OR (
            UPPER(vddep.validity) > CURRENT_TIMESTAMP
                AND
            LOWER(vddep.validity) <= CURRENT_TIMESTAMP
            )
        );

    RETURN data_elements;
END;
$$ LANGUAGE plpgsql;
