--
-- table: product
-- description: this table lists the possible products: domain, contact, host, ssl, email, ...
--

CREATE TABLE product (
  id   UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  UNIQUE(name)
);

--
-- table: order_type
-- description: this table lists the possible order types.
--

CREATE TABLE order_type (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES product(id),
  name       TEXT NOT NULL,
  UNIQUE (product_id,name)
);

--
-- table: order_status
-- description: this table lists the possible order statuses.
--

CREATE TABLE order_status (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  descr      TEXT NOT NULL,
  is_final   BOOLEAN NOT NULL,
  is_success BOOLEAN NOT NULL,
  UNIQUE (name)
);


--
-- table: order_status
-- description: this table lists the possible order statuses.
--

CREATE TABLE order_item_status (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  descr      TEXT NOT NULL,
  is_final   BOOLEAN NOT NULL,
  is_success BOOLEAN NOT NULL,
  UNIQUE (name)
);


CREATE TABLE order_status_path(
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name                  TEXT NOT NULL UNIQUE,
  descr                 TEXT
);

COMMENT ON TABLE order_status_path IS 
'Names the valid "paths" that an order can take, this allows for flexibility on the possibility
of using multiple payment methods that may or may not offer auth/capture.';


CREATE TABLE order_status_transition (
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  path_id               UUID NOT NULL REFERENCES order_status_path ON DELETE CASCADE,
  from_id               UUID NOT NULL REFERENCES order_status ON DELETE CASCADE,
  to_id                 UUID NOT NULL REFERENCES order_status ON DELETE CASCADE,
  UNIQUE(path_id,from_id,to_id)
);

COMMENT ON TABLE order_status_transition IS
'tuples in this table become valid status transitions for orders';

--
-- table: order
-- description: this table stores global attributes common to all types of orders.
--

CREATE TABLE "order" (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_customer_id UUID NOT NULL REFERENCES tenant_customer,
  type_id            UUID NOT NULL REFERENCES order_type,
  customer_user_id   UUID REFERENCES customer_user,
  status_id          UUID NOT NULL REFERENCES order_status 
                     DEFAULT tc_id_from_name('order_status','created'),
  path_id            UUID NOT NULL REFERENCES order_status_path
                     DEFAULT tc_id_from_name('order_status_path','default'),
  metadata           JSONB DEFAULT '{}'::JSONB
) INHERITS (class.audit_trail);


CREATE TRIGGER order_set_metadata_tg
  BEFORE INSERT ON "order"
  FOR EACH ROW  WHEN (NOT is_data_migration() ) EXECUTE PROCEDURE order_set_metadata();

CREATE TRIGGER order_process_items_tg 
  AFTER UPDATE ON "order" 
  FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id AND NEW.status_id = tc_id_from_name('order_status','processing'))
  EXECUTE PROCEDURE order_process_items();
COMMENT ON TRIGGER order_process_items_tg ON "order" IS 'mark the order items to be ready to be processed';

CREATE TRIGGER order_on_failed_tg
    AFTER UPDATE ON "order"
    FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id AND NEW.status_id = tc_id_from_name('order_status','failed'))
EXECUTE PROCEDURE order_on_failed();

CREATE TRIGGER order_status_transition_tg
  AFTER UPDATE OF status_id ON "order"
  FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id)
  EXECUTE PROCEDURE notify_order_status_transition_tgf();
COMMENT ON TRIGGER order_status_transition_tg ON "order" IS 'send an notification on an order status transition to a global channel';

CREATE TRIGGER order_status_transition_orderid_tg
  AFTER UPDATE OF status_id ON "order"
  FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id)
  EXECUTE PROCEDURE notify_order_status_transition_orderid_tgf();
COMMENT ON TRIGGER order_status_transition_orderid_tg ON "order" IS 'send an notification on an order status transition to an order id specific channel';

CREATE TRIGGER order_status_transition_final_tg
  AFTER UPDATE OF status_id ON "order"
  FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id AND (NEW.status_id = tc_id_from_name('order_status', 'successful') OR NEW.status_id = tc_id_from_name('order_status', 'failed')))
  EXECUTE PROCEDURE notify_order_status_transition_final_tfg();
COMMENT ON TRIGGER order_status_transition_final_tg ON "order" IS 'send a notification to the order manager service when an order is completed';

--
-- table: order_item
-- description: this table is a template for all order_item_+ tables.
--

CREATE TABLE order_item (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id                UUID NOT NULL REFERENCES "order",
  status_id               UUID NOT NULL REFERENCES order_item_status
                          DEFAULT tc_id_from_name('order_item_status','pending'),
  parent_order_item_id    UUID REFERENCES order_item(id)
) INHERITS (class.audit);

CREATE INDEX ON order_item(order_id);
CREATE INDEX ON order_item(parent_order_item_id);

-- prevents records to be directly inserted into the order_item table
CREATE TRIGGER order_item_prevent_insert_tg
  BEFORE INSERT ON order_item
  FOR EACH ROW EXECUTE PROCEDURE order_item_prevent_insert();


--
-- table: order_contact
-- description: contacts that are available for this order (created by caller)
--

CREATE TABLE order_contact(
    order_id           UUID NOT NULL REFERENCES "order",
    PRIMARY KEY(id)
) INHERITS(contact);

COMMENT ON TABLE order_contact IS
'will be dropped in favour of order_item_create_contact';

CREATE OR REPLACE TRIGGER a_order_prevent_if_short_id_exists_tg
    BEFORE INSERT ON order_contact
    FOR EACH ROW WHEN (
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE order_prevent_if_short_id_exists();

--
-- table: order_contact_postal
-- description: postal information associated with the above order_contact
--

CREATE TABLE order_contact_postal(
  FOREIGN KEY (contact_id) REFERENCES order_contact,
  PRIMARY KEY(id)
) INHERITS(contact_postal);

--
-- table: order_contact_attribute
-- description: further attributes associated with the above order_contact
--

CREATE TABLE order_contact_attribute(
 FOREIGN KEY (contact_id) REFERENCES order_contact,
 PRIMARY KEY(id)
) INHERITS(contact_attribute);

CREATE OR REPLACE TRIGGER contact_attribute_insert_value_tg BEFORE INSERT ON order_contact_attribute
  FOR EACH ROW
  EXECUTE FUNCTION filter_contact_attribute_value_tgf();

-- TODO: How to handle already stored contact attributes which are missing from the update. 
CREATE OR REPLACE TRIGGER contact_attribute_update_value_tg BEFORE UPDATE ON order_contact_attribute
  FOR EACH ROW
  EXECUTE FUNCTION filter_contact_attribute_value_tgf();

--
-- table: order_item_plan_status
-- description: this is the execution plan status to provision the order.
--

CREATE TABLE order_item_plan_status(
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name                  TEXT NOT NULL UNIQUE,
  descr                 TEXT,
  is_success            BOOLEAN NOT NULL,
  is_final              BOOLEAN NOT NULL
) INHERITS(class.audit);

-- only two possible is_final
CREATE UNIQUE INDEX ON order_item_plan_status(is_success,is_final) WHERE is_final;

--
-- table: order_item_plan_valiation_status
-- description: this is the validation plan status to provision the order.
--

CREATE TABLE order_item_plan_validation_status(
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name                  TEXT NOT NULL UNIQUE,
  descr                 TEXT,
  is_success            BOOLEAN NOT NULL,
  is_final              BOOLEAN NOT NULL
) INHERITS(class.audit);

-- only two possible is_final
CREATE UNIQUE INDEX ON order_item_plan_validation_status(is_success,is_final) WHERE is_final;


CREATE TABLE order_item_object(
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name                  TEXT NOT NULL UNIQUE,
  descr                 TEXT
) INHERITS(class.audit);


CREATE TABLE order_item_strategy(
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  order_type_id           UUID NOT NULL REFERENCES order_type,
  provider_instance_id    UUID REFERENCES provider_instance,
  object_id               UUID NOT NULL REFERENCES order_item_object,
  provision_order         INT  NOT NULL DEFAULT 1,
  is_validation_required  BOOLEAN NOT NULL DEFAULT FALSE
);

--
-- table: order_item_plan
-- description: this is the execution plan to provision the order.
--
CREATE TABLE order_item_plan (
    id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    order_item_id           UUID NOT NULL,  --REFERENCES order_item,
    parent_id               UUID REFERENCES order_item_plan,
    status_id               UUID NOT NULL REFERENCES order_item_plan_status
                            DEFAULT tc_id_from_name('order_item_plan_status','new'),
    validation_status_id    UUID NOT NULL REFERENCES order_item_plan_validation_status
                            DEFAULT tc_id_from_name('order_item_plan_validation_status','pending'),
    order_item_object_id    UUID NOT NULL REFERENCES order_item_object,
    reference_id            UUID,
    result_message          TEXT,
    result_data             JSONB,
    provision_order         INT,
    UNIQUE(order_item_id,order_item_object_id)
);
CREATE INDEX ON order_item_plan(parent_id);

COMMENT ON TABLE order_item_plan IS 
'stores the plan on how an order must be provisioned';

COMMENT ON COLUMN order_item_plan.reference_id IS 
'since a foreign key would depend on the `order_item_object_id` type, to simplify the setup 
the reference_id is used to conditionally point to rows in the `create_domain_*` tables';

--
-- table: order_host
-- description: hosts that are available for this order 
--

CREATE TABLE order_host(
  CONSTRAINT order_host_pkey PRIMARY KEY (id),
	CONSTRAINT order_host_tenant_customer_id_fkey FOREIGN KEY (tenant_customer_id) REFERENCES public.tenant_customer(id)
) INHERITS(host);

CREATE TRIGGER trigger_validate_name_fqdn
    BEFORE INSERT ON order_host
    FOR EACH ROW WHEN(NEW.name <> '')EXECUTE FUNCTION validate_name_fqdn();

--
-- table: order_host_addr
-- description: addresses that are available for this order_host
--

CREATE TABLE order_host_addr(
  FOREIGN KEY (host_id) REFERENCES order_host,
  PRIMARY KEY(id),
  UNIQUE(host_id, address)
) INHERITS(host_addr);

--
-- table: order_item_price
-- description: price data (price and currency) for the order item
--

CREATE TABLE order_item_price(
  id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  order_item_id       UUID NOT NULL,
  tenant_customer_id  UUID NOT NULL REFERENCES tenant_customer,
  currency_type_id    UUID NOT NULL REFERENCES currency_type,
  price               FLOAT NOT NULL
);

\i create_domain.ddl
\i renew_domain.ddl
\i redeem_domain.ddl
\i delete_domain.ddl
\i update_domain.ddl
\i transfer_domain.ddl
\i transfer_away_domain.ddl
\i import_domain.ddl
\i create_contact.ddl
\i update_contact.ddl
\i create_host.ddl
\i create_hosting.ddl
\i delete_hosting.ddl
\i update_hosting.ddl
\i delete_contact.ddl
\i update_host.ddl
\i delete_host.ddl
\i internal.ddl
