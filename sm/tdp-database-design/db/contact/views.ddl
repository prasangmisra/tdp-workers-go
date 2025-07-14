CREATE OR REPLACE VIEW v_contact_attribute AS
WITH RECURSIVE attrs(attribute_id,attribute_name,attribute_descr,attribute_key) AS (
    SELECT 
        a.id AS attribute_id,
        a.name AS attribute_name,
        a.descr AS attribute_descr, 
        a.name AS attribute_key
    FROM attribute a 
    WHERE a.parent_id IS NULL 

    UNION 

    SELECT 
        a.id AS attribute_id,
        a.name AS attribute_name,
        a.descr AS attribute_descr,
        FORMAT('%s.%s',attrs.attribute_name,a.name) AS attribute_key
    FROM attribute a
        JOIN attrs ON attrs.attribute_id = a.parent_id
)

SELECT 
    ca.contact_id,
    JSONB_OBJECT_AGG(a.attribute_key,ca.value) AS attributes
FROM ONLY contact_attribute ca 
    LEFT JOIN attrs a ON a.attribute_id = ca.attribute_id
GROUP BY 1    
;

--
-- view: v_contact
-- description: returns entire contacts with multiple rows per contact
--

CREATE OR REPLACE VIEW v_contact AS
SELECT
    c.id,
    tc_name_from_id('contact_type', c.type_id) AS contact_type,
    c.tenant_customer_id,
    c.email,
    c.phone,
    c.phone_ext,
    c.fax,
    c.fax_ext,
    c.language,
    c.tags,
    c.documentation,
    cp.is_international,
    cp.first_name,
    cp.last_name,
    c.title,
    cp.org_name,
    c.org_reg,
    c.org_vat,
    c.org_duns,
    cp.address1,
    cp.address2,
    cp.address3,
    cp.city,
    cp.postal_code,
    cp.state,
    c.country,
    vca.attributes
FROM ONLY contact c
JOIN ONLY contact_postal         cp ON cp.contact_id=c.id
LEFT JOIN v_contact_attribute vca ON vca.contact_id=c.id;

