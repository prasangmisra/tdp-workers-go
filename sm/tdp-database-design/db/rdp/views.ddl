--
-- view: v_data_element
-- description: This view aggregates data elements hierarchy 
--

DROP VIEW IF EXISTS v_data_element;
CREATE OR REPLACE VIEW v_data_element AS

WITH RECURSIVE element AS (
    SELECT id, NULL::UUID AS parent_id, NULL AS parent_name, name, name AS full_name, descr FROM data_element WHERE parent_id IS NULL
    UNION 
    SELECT c.id, p.id AS parent_id, p.name AS parent_name, c.name, p.name || '.' || c.name AS full_name, c.descr FROM data_element c 
    JOIN element p ON p.id = c.parent_id 
)
SELECT * FROM element;


--
-- view: v_domain_data_element_permission
-- description: This view aggregates data elements and their associated permissions
--

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

--
-- view: v_rdp_data_element
-- description: This view aggregates RDP data elements and their associated permissions
--

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
