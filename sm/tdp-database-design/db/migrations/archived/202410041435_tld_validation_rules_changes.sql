--
-- table: validation_rule
-- description: this table stores validation rules
--

CREATE TABLE validation_rule(
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    descr           TEXT,
    rule            TEXT NOT NULL,
    tags            TEXT[],
    metadata        JSONB
) INHERITS (class.audit_trail);

CREATE INDEX ON validation_rule USING GIN(tags);
CREATE INDEX ON validation_rule USING GIN(metadata);

--
-- table: tld_validation_rule
-- description: this table stores the relationship between TLDs, order types and validation rules
--

CREATE TABLE tld_validation_rule(
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tld_id              UUID REFERENCES tld,
    order_type_id       UUID REFERENCES order_type,
    validation_rule_id  UUID NOT NULL REFERENCES validation_rule,
    UNIQUE(tld_id, order_type_id, validation_rule_id)
) INHERITS (class.audit_trail);

DROP VIEW IF EXISTS v_tld_validation_rules;

--
-- view: v_tld_validation_rules
-- description: this view returns the validation rules associated with TLDs and order types
--

CREATE OR REPLACE VIEW v_tld_validation_rules AS
SELECT
    vr.id AS id,
    vr.name AS name,
    vr.descr AS descr,
    vr.rule AS rule,
    t.name AS tld_name,
    ot.name AS order_type_name,
    p.name AS product_name
FROM
    validation_rule vr
        LEFT JOIN tld_validation_rule tvr ON vr.id = tvr.validation_rule_id
        LEFT JOIN tld t ON tvr.tld_id = t.id
        LEFT JOIN order_type ot ON tvr.order_type_id = ot.id
        LEFT JOIN product p ON ot.product_id = p.id;

