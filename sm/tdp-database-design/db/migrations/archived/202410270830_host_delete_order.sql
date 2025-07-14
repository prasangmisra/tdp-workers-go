-- add provision_host_delete job type

INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key,
    is_noop
)
VALUES
(
    'provision_host_delete',
    'Deletes host in domain specific backend',
    'provision_host_delete',
    'provision_status',
    'status_id',
    'WorkerJobHostProvision',
    FALSE
)
ON CONFLICT DO NOTHING;


--- new order item strategy for delete host order ---

INSERT INTO order_item_strategy(order_type_id,object_id,provision_order) VALUES
(
    (SELECT type_id FROM v_order_product_type WHERE product_name='host' AND type_name='delete'),
    tc_id_from_name('order_item_object','host'),
    1
)
ON CONFLICT DO NOTHING;


--- tld settings for host delete order ---

INSERT INTO attr_key (
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null
) 
VALUES 
(
  'host_delete_rename_allowed',
  (SELECT id FROM attr_category WHERE name='order'),
  'Registry supports renaming host during delete',
  (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
  FALSE::TEXT,
  FALSE
), 
(
  'host_delete_rename_domain',
  (SELECT id FROM attr_category WHERE name='order'),
  'Registry supports renaming host during delete with domain',
  (SELECT id FROM attr_value_type WHERE name='TEXT'),
  ''::TEXT,
  FALSE
) ON CONFLICT DO NOTHING;


-- alter table host_addr to ON DELETE CASCADE for host_id
ALTER TABLE host_addr
DROP CONSTRAINT IF EXISTS host_addr_host_id_fkey;

ALTER TABLE host_addr
ADD CONSTRAINT host_addr_host_id_fkey
FOREIGN KEY (host_id) REFERENCES host(id)
ON DELETE CASCADE;


------ delete host order validation -----------

-- function: order_prevent_host_in_use()
-- description: check if host is associated with any domain
CREATE OR REPLACE FUNCTION order_prevent_host_in_use() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM ONLY domain_host WHERE host_id = NEW.host_id;

    IF FOUND THEN
        RAISE EXCEPTION 'cannot delete host: in use.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--
-- table: order_item_delete_host
-- description: this table stores attributes of host related orders.
--

CREATE TABLE IF NOT EXISTS order_item_delete_host (
  host_id UUID,
  host_name FQDN,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

-- prevents order creation for non-existing host
CREATE OR REPLACE TRIGGER a_order_prevent_if_host_does_not_exist_tg
  BEFORE INSERT ON order_item_delete_host
  FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_host_does_not_exist();

-- prevents order creation if host is associated with any domain
CREATE OR REPLACE TRIGGER b_order_prevent_host_in_use_tg
  BEFORE INSERT ON order_item_delete_host
  FOR EACH ROW EXECUTE PROCEDURE order_prevent_host_in_use();

-- make sure the initial status is 'pending'
CREATE OR REPLACE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_delete_host
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- creates an execution plan for the item
CREATE OR REPLACE TRIGGER a_order_item_create_plan_tg
  AFTER UPDATE ON order_item_delete_host
  FOR EACH ROW WHEN (
  OLD.status_id <> NEW.status_id
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE plan_simple_order_item();

-- starts the execution of the order
CREATE OR REPLACE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_delete_host
  FOR EACH ROW WHEN (
  OLD.status_id <> NEW.status_id
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE OR REPLACE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_delete_host
  FOR EACH ROW WHEN (
  OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish();

CREATE INDEX ON order_item_delete_host(order_id);
CREATE INDEX ON order_item_delete_host(status_id);


------ delete host order views -----------

CREATE OR REPLACE VIEW v_order_item_plan_object AS 
SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_contact.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM create_domain_contact
    WHERE create_domain_id = d.id
  ) AS distinct_order_contact ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_host.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
  JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM create_domain_nameserver
    WHERE create_domain_id = d.id
  ) AS distinct_order_host ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_renew_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id AS object_id,
  d.id AS id
FROM order_item_redeem_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj on obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_delete_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_transfer_in_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_transfer_away_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_host.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
  JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM update_domain_add_nameserver
    WHERE update_domain_id = d.id
  ) AS distinct_order_host ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_contact.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM update_domain_contact
    WHERE update_domain_id = d.id
  ) AS distinct_order_contact ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting_certificate'

UNION


SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_delete_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_update_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_create_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_update_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_delete_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_update_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_delete_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
;


DROP VIEW IF EXISTS v_order_delete_host;
CREATE OR REPLACE VIEW v_order_delete_host AS
SELECT
    dh.id AS order_item_id,
    dh.order_id AS order_id,
    dh.host_id AS host_id,
    dh.host_name AS host_name,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name AS customer_name
FROM order_item_delete_host dh
    JOIN ONLY host h ON h.id = dh.host_id
    JOIN "order" o ON o.id=dh.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;


------ delete host provision -----------

-- function: plan_delete_host_provision()
-- description: delete a host based on the plan
CREATE OR REPLACE FUNCTION plan_delete_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_host               RECORD;
    v_host_parent_domain        RECORD;
BEGIN
    -- order information
    SELECT * INTO v_delete_host
    FROM v_order_delete_host
    WHERE order_item_id = NEW.order_item_id;

    v_host_parent_domain := get_host_parent_domain(v_delete_host.host_name, v_delete_host.tenant_customer_id);

    IF v_host_parent_domain IS NULL THEN
        -- delete host locally only
        DELETE FROM ONLY host where id=v_delete_host.host_id;

        -- mark plan as completed to complete the order
        UPDATE delete_host_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- insert into provision_host with normal flow
    INSERT INTO provision_host_delete(
        host_id,
        name,
        domain_id,
        accreditation_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_delete_host.host_id,
        v_delete_host.host_name,
        v_host_parent_domain.id,
        v_host_parent_domain.accreditation_id,
        v_delete_host.tenant_customer_id,
        v_delete_host.order_metadata,
        ARRAY [NEW.id]
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- this table contains the plan for deleting a host
CREATE TABLE IF NOT EXISTS delete_host_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_delete_host
) INHERITS(order_item_plan,class.audit_trail);

CREATE OR REPLACE TRIGGER plan_delete_host_provision_host_tg
  AFTER UPDATE ON delete_host_plan
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host')
  )
  EXECUTE PROCEDURE plan_delete_host_provision();

CREATE OR REPLACE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_host_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE OR REPLACE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON delete_host_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();


-- function: provision_host_delete_job()
-- description: creates the job to delete the host
CREATE OR REPLACE FUNCTION provision_host_delete_job() RETURNS TRIGGER AS $$
DECLARE
    v_host  RECORD;
BEGIN
    SELECT
        NEW.id AS provision_host_delete_id,
        NEW.host_id AS host_id,
        NEW.name AS host_name,
        NEW.tenant_customer_id AS tenant_customer_id,
        get_tld_setting(
            p_key=>'tld.order.host_delete_rename_allowed',
            p_tld_name=>tld_part(NEW.name)
        )::BOOL AS host_delete_rename_allowed,
        get_tld_setting(
            p_key=>'tld.order.host_delete_rename_domain',
            p_tld_name=>tld_part(NEW.name)
        )::TEXT AS host_delete_rename_domain,
        TO_JSONB(va.*) AS accreditation,
        NEW.order_metadata AS metadata
    INTO v_host
    FROM v_accreditation va
    WHERE va.accreditation_id = NEW.accreditation_id;

    UPDATE provision_host_delete SET job_id=job_submit(
        NEW.tenant_customer_id,
        'provision_host_delete',
        NEW.id,
        TO_JSONB(v_host.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_host_delete_success()
-- description: deletes the host once the provision job completes
CREATE OR REPLACE FUNCTION provision_host_delete_success() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM ONLY host where id=NEW.host_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--
-- table: provision_host_delete
-- description: this table is for provisioning a domain host delete in the backend.
--

CREATE TABLE IF NOT EXISTS provision_host_delete (
  host_id                 UUID NOT NULL,
  name                    TEXT NOT NULL,
  domain_id               UUID REFERENCES domain,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

-- starts the host delete order provision
CREATE OR REPLACE TRIGGER provision_host_delete_job_tg
  AFTER INSERT ON provision_host_delete
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending')
  ) EXECUTE PROCEDURE provision_host_delete_job();

-- completes the host delete order provision
CREATE OR REPLACE TRIGGER provision_host_delete_success_tg
  AFTER UPDATE ON provision_host_delete
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_host_delete_success();

\i triggers.ddl
\i provisioning/triggers.ddl
