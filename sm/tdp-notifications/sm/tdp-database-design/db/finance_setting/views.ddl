DROP VIEW IF EXISTS v_finance_setting CASCADE;
CREATE OR REPLACE VIEW v_finance_setting AS 
SELECT 
    fst.name, 
    COALESCE(
        fs.value_integer::TEXT,    
        fs.value_decimal::TEXT, 
        fs.value_text::TEXT,  
        fs.value_boolean::TEXT, 
        fs.value_uuid::TEXT, 
        fs.value_text_list::TEXT 
    ) AS value,
    CASE
        WHEN fs.tenant_id IS NULL 
             AND fs.tenant_customer_id IS NULL 
             AND fs.provider_instance_tld_id IS NULL 
        THEN TRUE
        ELSE FALSE
    END AS is_default, 
    fs.id, 
    fs.tenant_id,
    fs.tenant_customer_id,
    fs.provider_instance_tld_id,
    fs.type_id,
    "fs".validity
    FROM finance_setting fs 
	JOIN finance_setting_type fst ON fst.id = fs.type_id
	ORDER BY fst.name, is_default DESC; 