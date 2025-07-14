--
-- view: v_template_section
-- description: this view lists all template sections with corresponding template data and section order
--

CREATE OR REPLACE VIEW v_template_section AS
SELECT
    template_id,
    subject,
    template_type_id,
    language_id,
    status_id,
    engine_id,
    validity,
    created_date,
    updated_date,
    section_type,
    section_content,
    tenant_id,
    tenant_customer_id,
    ROW_NUMBER() OVER (PARTITION BY template_id ORDER BY 
        section_seq ASC, -- order by section type sequence
        position ASC -- order by section position within template
    ) AS section_order
FROM (
    SELECT 
        t.id AS template_id,
        t.subject,
        t.type_id AS template_type_id,
        t.language_id,
        t.status_id,
        t.engine_id,
        t.validity,
        t.created_date,
        t.updated_date,
        st.name AS section_type,
        st.seq AS section_seq,
        t.content AS section_content,
        t.tenant_id,
        t.tenant_customer_id,
        0 AS position -- content of template body is always comes first
    FROM template t
    JOIN section_type st ON st.name = 'body'
    WHERE content IS NOT NULL AND content != ''

    UNION ALL

    SELECT
        t.id AS template_id,
        t.subject,
        t.type_id AS template_type_id,
        t.language_id,
        t.status_id,
        t.engine_id,
        t.validity,
        t.created_date,
        t.updated_date,
        st.name AS section_type,
        st.seq AS section_seq,
        s.content AS section_content,
        t.tenant_id,
        t.tenant_customer_id,
        ts.position
    FROM template t
    JOIN template_section ts ON ts.template_id = t.id
    JOIN section s ON s.id = ts.section_id
    JOIN section_type st ON st.id = s.type_id

) AS template_sections;

--
-- view: v_template
-- description: this view lists all most recent, valid templates combined and ready to use per template type, tenant and tenant customer
--

CREATE OR REPLACE VIEW v_template AS
SELECT DISTINCT ON (tt.id, precedence) 
    vts.template_id,
    vts.subject,
    vts.template_type_id,
    tt.name AS template_type,
    vts.language_id,
    l.name AS language,
    vts.created_date,
    vts.updated_date,
    string_agg(vts.section_content, E'\n' ORDER BY vts.section_order) AS content,
    vts.tenant_id,
    vts.tenant_customer_id,
    CASE 
        WHEN vts.tenant_id IS NOT NULL AND vts.tenant_customer_id IS NOT NULL THEN 1
        WHEN vts.tenant_id IS NOT NULL AND vts.tenant_customer_id IS NULL THEN 2
        ELSE 3
    END AS precedence
FROM v_template_section vts
JOIN template_type tt ON tt.id = vts.template_type_id
JOIN template_status tss ON tss.id = vts.status_id
JOIN language l ON l.id = vts.language_id
WHERE
    tss.name = 'published'
    AND
    CURRENT_TIMESTAMP BETWEEN LOWER(vts.validity) AND UPPER(vts.validity)
GROUP BY 
	precedence,
    vts.template_id,
    vts.subject,
    vts.template_type_id,
    tt.id,
    tt.name,
    vts.language_id,
    l.name,
    vts.created_date,
    vts.updated_date,
    vts.tenant_id,
    vts.tenant_customer_id
ORDER BY
    tt.id,
    precedence,
    vts.created_date DESC;


--
-- view: v_notification_template
-- description: this view lists all template with combined sections for given notification type
--
   
CREATE OR REPLACE VIEW v_notification_template AS
SELECT
    ntt.notification_type_id,
    vt.template_id,
    vt.subject,
    vt.template_type_id,
    vt.template_type,
    vt.language,
    vt.content,
    vt.tenant_id,
    vt.tenant_customer_id
FROM notification_template_type ntt
JOIN v_template vt ON vt.template_type_id = ntt.template_type_id;
