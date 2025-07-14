DROP VIEW IF EXISTS v_attr_value CASCADE;
CREATE OR REPLACE VIEW v_attr_value AS
SELECT
    tn.id AS tenant_id,
    tn.name AS tenant_name,
    k.category_id,
    ag.name AS category_name,
    k.id AS key_id,
    k.name AS key_name,
    vt.name AS data_type_name,
    vt.data_type,
    COALESCE(
        av.value_integer::TEXT,      
        av.value_text::TEXT,         
        av.value_integer_range::TEXT,
        av.value_boolean::TEXT,      
        av.value_text_list::TEXT,    
        av.value_integer_list::TEXT,
        av.value_daterange::TEXT,
        av.value_tstzrange::TEXT,
        av.value_regex::TEXT,
        av.value_percentage::TEXT,
        k.default_value::TEXT
    ) AS value,
    av.id IS NULL AS is_default,
    av.tld_id,
    av.provider_instance_id,
    av.provider_id,
    av.registry_id
FROM attr_key k
    JOIN tenant tn ON TRUE
    JOIN attr_category ag ON ag.id = k.category_id
    JOIN attr_value_type vt ON vt.id = k.value_type_id
    LEFT JOIN attr_value av ON av.key_id = k.id AND tn.id = av.tenant_id
;
