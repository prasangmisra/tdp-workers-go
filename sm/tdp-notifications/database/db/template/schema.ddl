--
-- table: language
-- description: this table list the possible languages
--

CREATE TABLE "language" (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);

--
-- table: template_engine
-- description: this table list the possible templating engines
--

CREATE TABLE template_engine (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);

--
-- table: template_type
-- description: this table list the possible types of template
--

CREATE TABLE template_type (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);

--
-- table: template_status
-- description: this table list the possible statuses of template
--

CREATE TABLE template_status (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    descr   TEXT
);


--
-- table: template
-- description: this table list all templates available
--

CREATE TABLE template (
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

CREATE INDEX template_type_id_idx ON template(type_id);
CREATE INDEX template_language_id_idx ON template(language_id);
CREATE INDEX template_status_id_idx ON template(status_id);
CREATE INDEX template_engine_id_idx ON template(engine_id);
CREATE INDEX template_tenant_id_idx ON template(tenant_id);
CREATE INDEX template_tenant_customer_id_idx ON template(tenant_customer_id);


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

CREATE INDEX section_type_id_idx ON section(type_id);

--
-- table: template_section
-- description: this table maps sections to templates
--

CREATE TABLE template_section (
    template_id     UUID NOT NULL REFERENCES template,
    section_id      UUID NOT NULL REFERENCES section,
    position        INT NOT NULL CHECK (position > 0),
    PRIMARY KEY(template_id, section_id)
) INHERITS (class.audit_trail);

CREATE INDEX template_section_template_id_idx ON template_section(template_id);
CREATE INDEX template_section_section_id_idx ON template_section(section_id);

--
-- table: template_variable_type
-- description: this table list all template variable types available
--

CREATE TABLE variable_type(
    id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    data_type   REGTYPE NOT NULL
);

--
-- table: template_variable
-- description: this table list all template variable for given template type
--

CREATE TABLE template_variable (
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name                TEXT NOT NULL,
    descr               TEXT,
    type_id             UUID NOT NULL REFERENCES variable_type,
    template_type_id    UUID NOT NULL REFERENCES template_type
) INHERITS (class.audit_trail);

CREATE INDEX template_variable_template_type_id_idx ON template_variable(template_type_id);

--
-- table: section_variable
-- description: this table list all variable for given section
--

CREATE TABLE section_variable (
    id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name          TEXT NOT NULL,
    descr         TEXT,
    type_id       UUID NOT NULL REFERENCES variable_type,
    section_id    UUID NOT NULL REFERENCES section
) INHERITS (class.audit_trail);

CREATE INDEX section_variable_section_id_idx ON section_variable(section_id);

--
-- table: notification_template_type
-- description: this table maps notification types to template types
--

CREATE TABLE notification_template_type (
    notification_type_id    UUID NOT NULL REFERENCES notification_type,
    template_type_id        UUID NOT NULL REFERENCES template_type,
    PRIMARY KEY(notification_type_id, template_type_id)
) INHERITS (class.audit_trail);

CREATE INDEX notification_template_type_notification_type_id_idx ON notification_template_type(notification_type_id);

