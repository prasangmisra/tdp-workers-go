--
-- table: business_entity
-- description: this table stores attributes whatever business entity.
--

CREATE TABLE business_entity (
  id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name          TEXT NOT NULL,
  descr         TEXT NOT NULL,
  parent_id     UUID REFERENCES business_entity,
  UNIQUE(name)
) INHERITS (class.audit_trail,class.soft_delete);

--
-- table: tenant
-- description: this table stores attributes of brands and HRS's, for instance OpenSRS, Enom, Xneelo.
--

CREATE TABLE tenant (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  business_entity_id UUID NOT NULL REFERENCES business_entity,
  name               TEXT NOT NULL UNIQUE,
  descr              TEXT NOT NULL,
  UNIQUE(business_entity_id,name)
) INHERITS (class.audit_trail,class.soft_delete);

--
-- table: customer
-- description: this table stores attributes of customers (aka reseller or partner).
--

CREATE TABLE customer (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  business_entity_id UUID NOT NULL REFERENCES business_entity,
  parent_customer_id UUID REFERENCES customer,
  name               TEXT NOT NULL,
  descr              TEXT,
  UNIQUE(business_entity_id,name)
) INHERITS (class.audit_trail,class.soft_delete);

--
-- table: user
-- description: this table stores attributes of users acting on behalf of customers.
--

CREATE TABLE "user" (
  id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  email         TEXT NOT NULL,
  name          TEXT NOT NULL,
  UNIQUE(email)
) INHERITS (class.audit_trail,class.soft_delete);

--
-- table: tenant_customer
-- description: this table joins customers to one or more tenants.
--

CREATE TABLE tenant_customer (
  id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id           UUID NOT NULL REFERENCES tenant,
  customer_id         UUID NOT NULL REFERENCES customer,
  customer_number     TEXT NOT NULL,
  UNIQUE(tenant_id,customer_id),
  UNIQUE(tenant_id,customer_number)
) INHERITS (class.audit_trail,class.soft_delete);

--
-- table: tenant_customer_users
-- description: this table joins users to one or more customers.
--

CREATE TABLE customer_user (
  id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  customer_id     UUID NOT NULL REFERENCES customer,
  user_id         UUID NOT NULL REFERENCES "user",
  UNIQUE(customer_id,user_id)
) INHERITS (class.audit_trail,class.soft_delete);

