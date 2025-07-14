-- contact update related tables and views

-- function: plan_update_contact_provision()
-- description: update a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_contact_provision() RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Skipping, not implemented yet';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- table: order_item_update_contact
-- description: this table stores attributes of update contact related orders.
--
CREATE TABLE IF NOT EXISTS order_item_update_contact (
    contact_id UUID NOT NULL REFERENCES contact,
    new_contact_id UUID NOT NULL REFERENCES order_contact,
    reuse_behavior TEXT NOT NULL DEFAULT 'split'
        CHECK (reuse_behavior IN ('fail', 'split')),
    PRIMARY KEY (id),
    FOREIGN KEY (order_id) REFERENCES "order",
    FOREIGN KEY (status_id) REFERENCES order_item_status
)
INHERITS (
    order_item,
    class.audit_trail
);

-- make sure the initial status is 'pending'
CREATE OR REPLACE TRIGGER order_item_force_initial_status_tg
    BEFORE INSERT ON order_item_update_contact
    FOR EACH ROW
    EXECUTE PROCEDURE order_item_force_initial_status ();

-- creates an execution plan for the item
CREATE OR REPLACE TRIGGER a_order_item_create_plan_tg
    AFTER UPDATE ON order_item_update_contact
    FOR EACH ROW
    WHEN (OLD.status_id <> NEW.status_id AND NEW.status_id = tc_id_from_name ('order_item_status', 'ready'))
    EXECUTE PROCEDURE plan_simple_order_item ();

-- starts the execution of the order
CREATE OR REPLACE TRIGGER b_order_item_plan_start_tg
    AFTER UPDATE ON order_item_update_contact
    FOR EACH ROW
    WHEN (OLD.status_id <> NEW.status_id AND NEW.status_id = tc_id_from_name ('order_item_status', 'ready'))
    EXECUTE PROCEDURE order_item_plan_start ();

-- when the order_item completes
CREATE OR REPLACE TRIGGER order_item_finish_tg
    AFTER UPDATE ON order_item_update_contact
    FOR EACH ROW
    WHEN (OLD.status_id <> NEW.status_id)
    EXECUTE PROCEDURE order_item_finish ();

CREATE INDEX ON order_item_update_contact (order_id);

CREATE INDEX ON order_item_update_contact (status_id);

-- this table contains the plan for updating a contact
CREATE TABLE IF NOT EXISTS update_contact_plan (
    PRIMARY KEY (id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_update_contact
)
INHERITS (
    order_item_plan,
    class.audit_trail
);

CREATE OR REPLACE TRIGGER plan_update_contact_provision_tg
    AFTER UPDATE ON update_contact_plan
    FOR EACH ROW
    WHEN (OLD.status_id <> NEW.status_id AND NEW.status_id = tc_id_from_name ('order_item_plan_status', 'processing'))
    EXECUTE PROCEDURE plan_update_contact_provision ();

CREATE OR REPLACE TRIGGER order_item_plan_update_tg
    AFTER UPDATE ON update_contact_plan
    FOR EACH ROW
    WHEN (OLD.status_id <> NEW.status_id AND OLD.status_id = tc_id_from_name ('order_item_plan_status', 'processing'))
    EXECUTE PROCEDURE order_item_plan_update ();

DROP VIEW IF EXISTS v_order_update_contact;
CREATE OR REPLACE VIEW v_order_update_contact AS
SELECT
    uc.id AS order_item_id,
    uc.order_id AS order_id,
    uc.contact_id AS contact_id,
    uc.new_contact_id AS new_contact_id,
    uc.reuse_behavior AS reuse_behavior,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name,
    tc_name_from_id('contact_type',ct.id) AS contact_type,
    cp.first_name,
    cp.last_name,
    cp.org_name
FROM order_item_update_contact uc
         JOIN order_contact oc ON oc.id = uc.contact_id
         JOIN contact_type ct ON ct.id = oc.type_id
         JOIN order_contact_postal cp ON cp.contact_id = oc.id AND NOT cp.is_international
         JOIN "order" o ON o.id=uc.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
;


-- update views
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

;


