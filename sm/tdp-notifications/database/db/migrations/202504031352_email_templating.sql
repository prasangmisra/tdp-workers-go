CREATE EXTENSION IF NOT EXISTS btree_gist;

--
-- table: language
-- description: this table list the possible languages
--

CREATE TABLE IF NOT EXISTS "language" (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);

--
-- table: template_engine
-- description: this table list the possible templating engines
--

CREATE TABLE IF NOT EXISTS template_engine (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);

--
-- table: template_type
-- description: this table list the possible types of template
--

CREATE TABLE IF NOT EXISTS template_type (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);

--
-- table: template_status
-- description: this table list the possible statuses of template
--

CREATE TABLE IF NOT EXISTS template_status (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);


--
-- table: template
-- description: this table list all templates available
--

CREATE TABLE IF NOT EXISTS template (
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    type_id             UUID NOT NULL REFERENCES template_type,
    subject             TEXT NOT NULL,
    content             TEXT, -- optional if section with body type is not present
    status_id           UUID NOT NULL REFERENCES template_status,
    language_id         UUID NOT NULL REFERENCES "language" DEFAULT tc_id_from_name('language', 'en'),
    engine_id           UUID NOT NULL REFERENCES template_engine,
    validity            TSTZRANGE NOT NULL DEFAULT TSTZRANGE(NOW(), 'Infinity'),

    -- following columns are used for branding
    tenant_id           UUID,
    tenant_customer_id  UUID,

    CHECK ( lower(validity) >= CURRENT_DATE )
) INHERITS (class.audit_trail);

CREATE INDEX IF NOT EXISTS template_type_id_idx ON template(type_id);
CREATE INDEX IF NOT EXISTS template_language_id_idx ON template(language_id);
CREATE INDEX IF NOT EXISTS template_status_id_idx ON template(status_id);
CREATE INDEX IF NOT EXISTS template_engine_id_idx ON template(engine_id);
CREATE INDEX IF NOT EXISTS template_tenant_id_idx ON template(tenant_id);
CREATE INDEX IF NOT EXISTS template_tenant_customer_id_idx ON template(tenant_customer_id);

--
-- table: section_type
-- description: this table list the possible types of section
--

CREATE TABLE section_type (
    id       UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name     TEXT NOT NULL UNIQUE,
    seq      INT NOT NULL UNIQUE,
    descr    TEXT
);


--
-- table: section
-- description: this table list all sections available
--

CREATE TABLE section (
    id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name         TEXT NOT NULL,
    type_id      UUID NOT NULL REFERENCES section_type,
    content      TEXT NOT NULL
) INHERITS (class.audit_trail);

CREATE INDEX IF NOT EXISTS section_type_id_idx ON section(type_id);

--
-- table: template_section
-- description: this table maps sections to templates
--

CREATE TABLE IF NOT EXISTS template_section (
    template_id     UUID NOT NULL REFERENCES template,
    section_id      UUID NOT NULL REFERENCES section,
    position        INT NOT NULL CHECK (position > 0),
    PRIMARY KEY(template_id, section_id)
) INHERITS (class.audit_trail);

CREATE INDEX IF NOT EXISTS template_section_template_id_idx ON template_section(template_id);
CREATE INDEX IF NOT EXISTS template_section_section_id_idx ON template_section(section_id);

--
-- table: template_variable_type
-- description: this table list all template variable types available
--

CREATE TABLE IF NOT EXISTS variable_type(
    id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    data_type   REGTYPE NOT NULL
);

--
-- table: template_variable
-- description: this table list all template variable for given template type
--

CREATE TABLE IF NOT EXISTS template_variable (
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name                TEXT NOT NULL,
    descr               TEXT,
    type_id             UUID NOT NULL REFERENCES variable_type,
    template_type_id    UUID NOT NULL REFERENCES template_type
) INHERITS (class.audit_trail);

CREATE INDEX IF NOT EXISTS template_variable_template_type_id_idx ON template_variable(template_type_id);

--
-- table: section_variable
-- description: this table list all variable for given section
--

CREATE TABLE IF NOT EXISTS section_variable (
    id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name          TEXT NOT NULL,
    descr         TEXT,
    type_id       UUID NOT NULL REFERENCES variable_type,
    section_id    UUID NOT NULL REFERENCES section
) INHERITS (class.audit_trail);

CREATE INDEX IF NOT EXISTS section_variable_section_id_idx ON section_variable(section_id);

--
-- table: notification_template_type
-- description: this table maps notification types to template types
--

CREATE TABLE IF NOT EXISTS notification_template_type (
    notification_type_id    UUID NOT NULL REFERENCES notification_type,
    template_type_id        UUID NOT NULL REFERENCES template_type,
    PRIMARY KEY(notification_type_id, template_type_id)
) INHERITS (class.audit_trail);

CREATE INDEX IF NOT EXISTS notification_template_type_notification_type_id_idx ON notification_template_type(notification_type_id);


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


INSERT INTO "language" (name, descr) 
    VALUES 
        ('en', 'English'),
        ('fr', 'French') ON CONFLICT (name) DO NOTHING;

INSERT INTO template_engine (name, descr) 
    VALUES 
        ('go-template', 'A Go template for dynamic content generation')
    ON CONFLICT (name) DO NOTHING;

INSERT INTO section_type (name, seq, descr) 
    VALUES 
        ('header', 10, 'Header section'),
        ('body', 20, 'Body section'),
        ('footer', 30, 'Footer section');

INSERT INTO template_status (name, descr) 
    VALUES 
        ('draft', 'Template is in draft mode'),
        ('published', 'Template is ready to be used')
    ON CONFLICT (name) DO NOTHING;

INSERT INTO variable_type (name, data_type)
    VALUES
      ('INTEGER','INTEGER'),
      ('TEXT','TEXT'),
      ('INTEGER_RANGE','INT4RANGE'),
      ('INTERVAL','INTERVAL'),
      ('BOOLEAN','BOOLEAN'),
      ('TEXT_LIST','TEXT[]'),
      ('INTEGER_LIST','INT[]'),
      ('DATERANGE','DATERANGE'),
      ('TSTZRANGE','TSTZRANGE')
    ON CONFLICT (name) DO NOTHING;

DROP VIEW IF EXISTS v_notification;
--
-- view: v_notification
-- description: this view lists all notifications with coresponding subscription channel
--

CREATE OR REPLACE VIEW v_notification AS
SELECT
    nd.id,
    n.id AS notification_id,
    nt.name AS type,
    n.payload,
    n.created_date,
    n.tenant_id,
    n.tenant_customer_id,
    ns.name AS status,
    nd.retries,
    nd.status_reason,
    sct.name AS channel_type,
    s.id AS subscription_id,
    swc.webhook_url,
    swc.signing_secret,
    s.status_id,
    template.subject AS email_subject,
    template.content AS email_template
FROM notification_delivery nd
JOIN notification_status ns ON ns.id = nd.status_id
JOIN notification n ON n.id = nd.notification_id
JOIN notification_type nt ON nt.id = n.type_id
LEFT JOIN subscription_poll_channel spc ON spc.id = nd.channel_id
LEFT JOIN subscription_webhook_channel swc ON swc.id = nd.channel_id
LEFT JOIN subscription_email_channel sec ON sec.id = nd.channel_id
JOIN subscription_channel_type sct ON sct.id IN (swc.type_id, sec.type_id, spc.type_id)
JOIN subscription s ON s.id IN (swc.subscription_id, sec.subscription_id, spc.subscription_id)
JOIN subscription_status ss ON ss.id = s.status_id
LEFT JOIN LATERAL (
    SELECT
        vnt.subject,
        vnt.content
    FROM v_notification_template vnt
    WHERE vnt.notification_type_id = nt.id
      AND (
          (vnt.tenant_id = n.tenant_id AND vnt.tenant_customer_id = n.tenant_customer_id)
          OR (vnt.tenant_id = n.tenant_id AND vnt.tenant_customer_id IS NULL)
          OR (vnt.tenant_id IS NULL AND vnt.tenant_customer_id IS NULL)
      )
    ORDER BY
        CASE
            WHEN vnt.tenant_id = n.tenant_id AND vnt.tenant_customer_id = n.tenant_customer_id THEN 1
            WHEN vnt.tenant_id = n.tenant_id AND vnt.tenant_customer_id IS NULL THEN 2
            WHEN vnt.tenant_id IS NULL AND vnt.tenant_customer_id IS NULL THEN 3
            ELSE 4
        END
    LIMIT 1
) template ON sct.name = 'email'
WHERE ss.name NOT IN ('paused', 'deactivated');



CREATE TRIGGER notification_delivery_update_tg INSTEAD OF UPDATE ON v_notification
    FOR EACH ROW EXECUTE PROCEDURE notification_delivery_update();
