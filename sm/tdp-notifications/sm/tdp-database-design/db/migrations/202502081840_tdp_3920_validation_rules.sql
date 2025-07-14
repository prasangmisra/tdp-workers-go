DROP TABLE IF EXISTS validation_rule;
DROP TABLE IF EXISTS tld_validation_rule;
DROP VIEW IF EXISTS v_tld_validation_rules;

CREATE OR REPLACE FUNCTION check_order_type_for_product() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.product_id IS NOT NULL AND NEW.order_type_id IS NOT NULL THEN
        PERFORM 1
        FROM order_type
        WHERE id = NEW.order_type_id AND product_id = NEW.product_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order type % does not exist for product %', NEW.order_type_id, NEW.product_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE validation_rule(
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    descr           TEXT,
    rule            TEXT NOT NULL,
    validity        TSTZRANGE NOT NULL DEFAULT TSTZRANGE(NOW(), 'Infinity'),
    tags            TEXT[],
    metadata        JSONB DEFAULT '{}'::JSONB,
    CHECK ( lower(validity) >= CURRENT_DATE )
) INHERITS (class.audit_trail);

CREATE INDEX ON validation_rule USING GIN(tags);
CREATE INDEX ON validation_rule USING GIN(metadata);

CREATE TABLE validation_association(
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tld_id              UUID REFERENCES tld,
    product_id          UUID REFERENCES product,
    order_type_id       UUID REFERENCES order_type,
    validation_rule_id  UUID NOT NULL REFERENCES validation_rule ON DELETE CASCADE
) INHERITS (class.audit_trail);

CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(product_id::TEXT, ''));
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(tld_id::TEXT, ''));
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(order_type_id::TEXT, ''));
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(tld_id::TEXT, ''), COALESCE(product_id::TEXT, ''));
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(tld_id::TEXT, ''), COALESCE(order_type_id::TEXT, ''));
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(product_id::TEXT, ''), COALESCE(order_type_id::TEXT, ''));
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(tld_id::TEXT, ''), COALESCE(product_id::TEXT, ''), COALESCE(order_type_id::TEXT, ''));

CREATE TRIGGER check_order_type_for_product_tg
    BEFORE INSERT OR UPDATE ON validation_association
    FOR EACH ROW EXECUTE PROCEDURE check_order_type_for_product();

DROP VIEW IF EXISTS v_validation_rule;
CREATE OR REPLACE VIEW v_validation_rule AS
SELECT
    vr.id AS id,
    vr.name AS name,
    vr.descr AS descr,
    vr.rule AS rule,
    (CURRENT_TIMESTAMP >= lower(vr.validity) AND CURRENT_TIMESTAMP <= upper(vr.validity)) AS is_active
FROM
    validation_rule vr;

DROP VIEW IF EXISTS v_validation_association;
CREATE OR REPLACE VIEW v_validation_association AS
SELECT
    vr.id AS id,
    vr.name AS name,
    vr.descr AS descr,
    vr.rule AS rule,
    t.name AS tld,
    p.name AS product,
    ot.name AS order_type,
    (CURRENT_TIMESTAMP >= lower(vr.validity) AND CURRENT_TIMESTAMP <= upper(vr.validity)) AS is_active
FROM
    validation_association a
        JOIN validation_rule vr ON a.validation_rule_id = vr.id
        LEFT JOIN tld t ON a.tld_id = t.id
        LEFT JOIN product p ON a.product_id = p.id
        LEFT JOIN order_type ot ON a.order_type_id = ot.id;