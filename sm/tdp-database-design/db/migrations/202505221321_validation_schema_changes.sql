-- 1a) Add the time-range to associations
ALTER TABLE validation_association
    ADD COLUMN validity TSTZRANGE NOT NULL
        DEFAULT TSTZRANGE(NOW(), 'Infinity');

-- 1b) Enforce “not in the past” on each association
ALTER TABLE validation_association
    ADD CONSTRAINT va_validity_check
        CHECK ( lower(validity) >= CURRENT_DATE );

DROP VIEW IF EXISTS v_validation_rule;
DROP VIEW IF EXISTS v_validation_association;

-- 1c) Drop it from the rule itself
ALTER TABLE validation_rule
    DROP COLUMN validity;

CREATE OR REPLACE VIEW v_validation_rule AS
SELECT
    vr.id AS id,
    vr.name AS name,
    vr.descr AS descr,
    vr.rule AS rule
FROM
    validation_rule vr;

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

-- 2a) Drop all unique indexes on validation_association

DROP INDEX IF EXISTS validation_association_validation_rule_id_coalesce_coalesc_idx1;
DROP INDEX IF EXISTS validation_association_validation_rule_id_coalesce_coalesc_idx2;
DROP INDEX IF EXISTS validation_association_validation_rule_id_coalesce_coalesc_idx3;
DROP INDEX IF EXISTS validation_association_validation_rule_id_coalesce_coalesce_idx;
DROP INDEX IF EXISTS validation_association_validation_rule_id_coalesce_idx;
DROP INDEX IF EXISTS validation_association_validation_rule_id_coalesce_idx1;
DROP INDEX IF EXISTS validation_association_validation_rule_id_coalesce_idx2;

-- 2b) Drop validation_rule validation_association fk constraint
ALTER TABLE validation_association
    DROP CONSTRAINT validation_association_validation_rule_id_fkey;

-- 2c) Forbid deleting a rule with active associations
ALTER TABLE validation_association
    ADD CONSTRAINT validation_association_validation_rule_id_fkey
        FOREIGN KEY(validation_rule_id)
            REFERENCES validation_rule(id)
            ON DELETE RESTRICT;

-- 2d) Only one "global" association per validation_rule_id
CREATE UNIQUE INDEX uniq_va_global
    ON validation_association (validation_rule_id)
    WHERE tld_id IS NULL AND product_id IS NULL AND order_type_id IS NULL;

-- 2e) Only one specific association per unique combination
CREATE UNIQUE INDEX uniq_va_specific
    ON validation_association (validation_rule_id, tld_id, product_id, order_type_id)
    WHERE tld_id IS NOT NULL OR product_id IS NOT NULL OR order_type_id IS NOT NULL;

-- 2f) Enforce uniqueness treating NULL as a value
CREATE UNIQUE INDEX uniq_va_all
    ON validation_association (
       validation_rule_id,
       COALESCE(tld_id, '00000000-0000-0000-0000-000000000000'),
       COALESCE(product_id, '00000000-0000-0000-0000-000000000000'),
       COALESCE(order_type_id, '00000000-0000-0000-0000-000000000000')
    );

-- Indexes for hottest queries
-- 3a) Lookup all active associations for “now”
CREATE INDEX idx_va_lower
    ON validation_association (tld_id, product_id, order_type_id, lower(validity));
CREATE INDEX idx_va_upper
    ON validation_association (tld_id, product_id, order_type_id, upper(validity));

-- 3b) Search by rule → associations
CREATE INDEX idx_va_by_rule
    ON validation_association (validation_rule_id) INCLUDE (tld_id, product_id, order_type_id, validity);