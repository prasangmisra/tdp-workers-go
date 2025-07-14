--
-- view: v_validation_rule
-- description: this view returns the validation rules

DROP VIEW IF EXISTS v_validation_rule;
CREATE OR REPLACE VIEW v_validation_rule AS
SELECT
    vr.id AS id,
    vr.name AS name,
    vr.descr AS descr,
    vr.rule AS rule
FROM
    validation_rule vr;

--
-- view: v_validation_association
-- description: this view returns the validation rule associations
--

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
    (CURRENT_TIMESTAMP >= lower(a.validity) AND CURRENT_TIMESTAMP <= upper(a.validity)) AS is_active
FROM
    validation_association a
        JOIN validation_rule vr ON a.validation_rule_id = vr.id
        LEFT JOIN tld t ON a.tld_id = t.id
        LEFT JOIN product p ON a.product_id = p.id
        LEFT JOIN order_type ot ON a.order_type_id = ot.id;