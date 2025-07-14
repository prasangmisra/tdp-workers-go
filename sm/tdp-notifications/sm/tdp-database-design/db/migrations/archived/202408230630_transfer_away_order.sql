-- rename order_type + add strategy
UPDATE order_type SET name = 'transfer_away' WHERE name = 'transfer_out';

INSERT INTO order_item_strategy(order_type_id,object_id,provision_order)
VALUES
(
    (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_away'),
        tc_id_from_name('order_item_object','domain'),
        1
);


-- function: order_prevent_if_domain_with_auth_info_does_not_exist()
-- description: check if domain with auth info exists
CREATE OR REPLACE FUNCTION order_prevent_if_domain_with_auth_info_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM domain d
    WHERE d.name = NEW.name
      AND d.auth_info = NEW.auth_info;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auth info does not match';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Transfer away domain order
CREATE TABLE order_item_transfer_away_domain (
    domain_id               UUID NOT NULL,
    name                    FQDN NOT NULL,
    transfer_status_id      UUID NOT NULL REFERENCES transfer_status,
    requested_by            TEXT NOT NULL,
    requested_date          TIMESTAMPTZ NOT NULL,
    action_by               TEXT NOT NULL,
    action_date             TIMESTAMPTZ NOT NULL,
    expiry_date             TIMESTAMPTZ NOT NULL,
    auth_info               TEXT,
    accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
    metadata                JSONB,
    PRIMARY KEY (id),
    FOREIGN KEY (order_id) REFERENCES "order",
    FOREIGN KEY (status_id) REFERENCES order_item_status
)
INHERITS (order_item, class.audit_trail);

-- make sure the initial status is 'pending'
CREATE TRIGGER order_item_force_initial_status_tg
    BEFORE INSERT ON order_item_transfer_away_domain
    FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- sets accreditation_tld_id from domain name when it does not contain one
CREATE TRIGGER order_item_set_tld_id_tg
    BEFORE INSERT ON order_item_transfer_away_domain
    FOR EACH ROW WHEN ( NEW.accreditation_tld_id IS NULL )
    EXECUTE PROCEDURE order_item_set_tld_id();

-- check if domain from order data exists
CREATE TRIGGER a_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_transfer_away_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();

-- check if provided auth info matches the domain auth info
CREATE TRIGGER order_prevent_if_domain_with_auth_info_does_not_exist_tg
    BEFORE UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN ( NEW.auth_info IS NOT NULL )
    EXECUTE PROCEDURE order_prevent_if_domain_with_auth_info_does_not_exist();

-- make sure the transfer auth info is valid
CREATE TRIGGER validate_auth_info_tg
    BEFORE UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN ( NEW.auth_info IS NOT NULL )
EXECUTE PROCEDURE validate_auth_info('transfer_away');

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_transfer_away_plan_tg
    AFTER UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    ) EXECUTE PROCEDURE plan_order_item();

-- starts the execution of the order
CREATE TRIGGER b_order_item_plan_start_tg
    AFTER UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('order_item_status','ready')
        AND NEW.transfer_status_id <> tc_id_from_name('transfer_status','pending')
    ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
    AFTER UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id
    ) EXECUTE PROCEDURE order_item_finish();

CREATE INDEX ON order_item_transfer_away_domain(order_id);
CREATE INDEX ON order_item_transfer_away_domain(status_id);

-- Transfer away domain plan
CREATE TABLE transfer_away_domain_plan (
    PRIMARY KEY(id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_transfer_away_domain
) INHERITS(order_item_plan,class.audit_trail);

CREATE TRIGGER order_item_plan_processed_tg
    AFTER UPDATE ON transfer_away_domain_plan
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id
    )
    EXECUTE PROCEDURE order_item_plan_processed ();

CREATE OR REPLACE VIEW v_order_transfer_away_domain AS
SELECT
    tad.id AS order_item_id,
    tad.order_id AS order_id,
    tad.accreditation_tld_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    s.is_final AS status_is_final,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name,
    at.provider_name,
    at.provider_instance_id,
    at.provider_instance_name,
    at.tld_id AS tld_id,
    at.tld_name AS tld_name,
    at.accreditation_id,
    d.name AS domain_name,
    d.id   AS domain_id,
    ts.name AS transfer_status_name,
    tad.transfer_status_id,
    tad.requested_by,
    tad.requested_date,
    tad.action_by,
    tad.action_date,
    tad.expiry_date,
    tad.auth_info,
    tad.metadata
FROM order_item_transfer_away_domain tad
    JOIN "order" o ON o.id=tad.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = tad.accreditation_tld_id
    JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=tad.name
    JOIN transfer_status ts ON ts.id = tad.transfer_status_id
;

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
;
