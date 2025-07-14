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
    metadata        JSONB DEFAULT '{}'::JSONB
) INHERITS (class.audit_trail);

CREATE INDEX ON validation_rule USING GIN(tags);
CREATE INDEX ON validation_rule USING GIN(metadata);

--
-- table: validation_association
-- description: this table stores the relationship between TLDs, order types, product types and validation rules
--

CREATE TABLE validation_association(
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tld_id              UUID REFERENCES tld,
    product_id          UUID REFERENCES product,
    order_type_id       UUID REFERENCES order_type,
    validation_rule_id  UUID NOT NULL REFERENCES validation_rule ON DELETE RESTRICT,
    validity        TSTZRANGE NOT NULL DEFAULT TSTZRANGE(NOW(), 'Infinity'),
    CHECK ( lower(validity) >= CURRENT_DATE )
) INHERITS (class.audit_trail);

-- Only one "global" association per validation_rule_id
CREATE UNIQUE INDEX uniq_va_global
    ON validation_association (validation_rule_id)
    WHERE tld_id IS NULL AND product_id IS NULL AND order_type_id IS NULL;

-- Only one specific association per unique combination
CREATE UNIQUE INDEX uniq_va_specific
    ON validation_association (validation_rule_id, tld_id, product_id, order_type_id)
    WHERE tld_id IS NOT NULL OR product_id IS NOT NULL OR order_type_id IS NOT NULL;

-- Enforce uniqueness treating NULL as a value
-- The UUID '00000000-0000-0000-0000-000000000000' is used as a placeholder for null values in the COALESCE function.
-- We should not use COALESCE(..., '') for UUID columns in PostgreSQL. The empty string '' is not a valid UUID and will cause a type error.
-- For UUID columns, use a valid UUID literal such as '00000000-0000-0000-0000-000000000000' as the default in COALESCE.
CREATE UNIQUE INDEX uniq_va_all
    ON validation_association (
       validation_rule_id,
       COALESCE(tld_id, '00000000-0000-0000-0000-000000000000'),
       COALESCE(product_id, '00000000-0000-0000-0000-000000000000'),
       COALESCE(order_type_id, '00000000-0000-0000-0000-000000000000')
    );

-- Indexes for hottest queries
-- 1a) Lookup all active associations for “now”
CREATE INDEX idx_va_lower ON validation_association (tld_id, product_id, order_type_id, lower(validity));
CREATE INDEX idx_va_upper ON validation_association (tld_id, product_id, order_type_id, upper(validity));

-- 1b) Search by rule → associations
CREATE INDEX idx_va_by_rule ON validation_association (validation_rule_id) INCLUDE (tld_id, product_id, order_type_id, validity);

CREATE TRIGGER check_order_type_for_product_tg
    BEFORE INSERT OR UPDATE ON validation_association
    FOR EACH ROW EXECUTE PROCEDURE check_order_type_for_product();
