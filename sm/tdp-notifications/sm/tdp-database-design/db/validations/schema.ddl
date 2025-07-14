--
-- table: validation_rule
-- description: this table stores validation rules
--

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

--
-- table: validation_association
-- description: this table stores the relationship between TLDs, order types, product types and validation rules
--

CREATE TABLE validation_association(
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tld_id              UUID REFERENCES tld,
    product_id          UUID REFERENCES product,
    order_type_id       UUID REFERENCES order_type,
    validation_rule_id  UUID NOT NULL REFERENCES validation_rule ON DELETE CASCADE
) INHERITS (class.audit_trail);

-- Ensure unique validation_rule_id and product_id, treating NULL product_id as unique
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(product_id::TEXT, ''));

-- Ensure unique validation_rule_id and tld_id, treating NULL tld_id as unique
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(tld_id::TEXT, ''));

-- Ensure unique validation_rule_id and order_type_id, treating NULL order_type_id as unique
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(order_type_id::TEXT, ''));

-- Ensure unique validation_rule_id, tld_id, and product_id, treating NULL values as unique
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(tld_id::TEXT, ''), COALESCE(product_id::TEXT, ''));

-- Ensure unique validation_rule_id, tld_id, and order_type_id, treating NULL values as unique
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(tld_id::TEXT, ''), COALESCE(order_type_id::TEXT, ''));

-- Ensure unique validation_rule_id, product_id, and order_type_id, treating NULL values as unique
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(product_id::TEXT, ''), COALESCE(order_type_id::TEXT, ''));

-- Ensure unique validation_rule_id, tld_id, product_id, and order_type_id, treating NULL values as unique
CREATE UNIQUE INDEX ON validation_association (validation_rule_id, COALESCE(tld_id::TEXT, ''), COALESCE(product_id::TEXT, ''), COALESCE(order_type_id::TEXT, ''));

CREATE TRIGGER check_order_type_for_product_tg
    BEFORE INSERT OR UPDATE ON validation_association
    FOR EACH ROW EXECUTE PROCEDURE check_order_type_for_product();
