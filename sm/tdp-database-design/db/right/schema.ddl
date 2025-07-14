
CREATE TABLE right_order (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY
, descr              TEXT
, block_matching     BOOLEAN NOT NULL DEFAULT TRUE
, order_type_id      UUID REFERENCES order_type(id)
, tenant_id          UUID REFERENCES tenant(id)
, customer_id        UUID REFERENCES customer(id)
, tenant_customer_id UUID REFERENCES tenant_customer(id)
, user_id            UUID REFERENCES "user"(id)
, product_id         UUID REFERENCES product(id)
) INHERITS ( class.audit, class.soft_delete );

COMMENT ON TABLE right_order IS '
';

COMMENT ON COLUMN right_order.block_matching IS '
Controls whether this right specification blocks or allows an operation when
matching with all the conditions. If set to true, the default value, an
operation matching the rights criteria will be blocked.

If set to false, an operation will be allowed if matching the conditions.
This can be used to carve exceptions in the rights. e.g.: "Block everything but
a domain renewal".
';

COMMENT ON COLUMN right_order.tenant_id IS '
When set to a non-NULL value, references the tenant to which this restriction
applies. The NULL value is a wildcard, causing this rule to apply to all
possible tenant.
';

COMMENT ON COLUMN right_order.order_type_id IS '
When set to a non-NULL value, references the order type to which this restriction
applies. The NULL value is a wildcard, causing this rule to apply to all
possible order type.
';

COMMENT ON COLUMN right_order.customer_id IS '
When set to a non-NULL value, references the customer to which this restriction
applies. The NULL value is a wildcard, causing this rule to apply to all
possible customer.
';

COMMENT ON COLUMN right_order.tenant_customer_id IS '
When set to a non-NULL value, references the tenant_customer to which this restriction
applies. The NULL value is a wildcard, causing this rule to apply to all
possible tenant_customers.
';

COMMENT ON COLUMN right_order.user_id IS '
When set to a non-NULL value, references the user to which this restriction
applies. The NULL value is a wildcard, causing this rule to apply to all
possible users.
';

COMMENT ON COLUMN right_order.product_id IS '
When set to a non-NULL value, references the product to which this restriction
applies. The NULL value is a wildcard, causing this rule to apply to all
possible products.
';
