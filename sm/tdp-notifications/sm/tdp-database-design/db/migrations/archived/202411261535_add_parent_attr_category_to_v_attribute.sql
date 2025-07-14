DROP VIEW IF EXISTS v_attribute CASCADE;
CREATE OR REPLACE VIEW v_attribute AS 

WITH RECURSIVE categories AS (
    SELECT id, name, descr, name AS parent_attr_category FROM attr_category WHERE parent_id IS NULL
    UNION 
    SELECT c.id, p.name || '.' || c.name, c.descr, p.name AS parent_attr_category FROM attr_category c JOIN categories p ON p.id = c.parent_id 
) 

SELECT DISTINCT
    vat.tenant_id,
    vat.tenant_name,
    vat.tld_name AS tld_name,
    vat.tld_id AS tld_id,
    vat.accreditation_tld_id,
    c.name AS path,
    c.id AS category_id,
    c.parent_attr_category,
    k.id AS key_id,
    avt.data_type,
    avt.name AS data_type_name,
    c.name || '.' || k.name AS key,
    COALESCE(vtld.value,vpi.value,vp.value,vpr.value,v.value,k.default_value) AS value,
    COALESCE(vtld.is_default,vpi.is_default,vp.is_default,vpr.is_default,v.is_default,TRUE) AS is_default
FROM v_accreditation_tld vat 
    JOIN categories c ON TRUE
    JOIN attr_key k ON k.category_id = c.id 
    JOIN attr_value_type avt ON avt.id = k.value_type_id
    LEFT JOIN v_attr_value v 
        ON  v.tenant_id = vat.tenant_id
        AND v.key_id = k.id
        AND COALESCE(v.tld_id,v.provider_instance_id,v.provider_id,v.registry_id) IS NULL
    LEFT JOIN v_attr_value vtld ON vtld.key_id = k.id AND vat.tld_id = vtld.tld_id
    LEFT JOIN v_attr_value vpi ON vpi.key_id = k.id AND vat.provider_instance_id = vpi.provider_instance_id
    LEFT JOIN v_attr_value vp ON vp.key_id = k.id AND vat.provider_id = vp.provider_id
    LEFT JOIN v_attr_value vpr ON vpr.key_id = k.id AND vat.registry_id = vpr.registry_id
ORDER BY tld_name,key;
