-- new order item strategy for update host order
INSERT INTO order_item_strategy(order_type_id,object_id,provision_order) VALUES
(
    (SELECT type_id FROM v_order_product_type WHERE product_name='host' AND type_name='update'),
    tc_id_from_name('order_item_object','host'),
    1
)
ON CONFLICT DO NOTHING;



-- function: order_prevent_if_host_does_not_exist()
-- description: check if host from order data exists
CREATE OR REPLACE FUNCTION order_prevent_if_host_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM only host WHERE id = NEW.host_id;

    IF NOT FOUND THEN 
        RAISE EXCEPTION 'Host ''%'' not found', NEW.host_id USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: check_and_populate_host_parent_domain()
-- description: check and populate host parent domain
CREATE OR REPLACE FUNCTION check_and_populate_host_parent_domain(_host RECORD) RETURNS RECORD AS $$
DECLARE
    _domains TEXT[];
    _domain  RECORD;
BEGIN
    IF _host.domain_id IS NOT NULL THEN
        SELECT * INTO _domain FROM domain WHERE id=_host.domain_id and tenant_customer_id=_host.tenant_customer_id;
    ELSE
        _domains := string_to_array(_host.name, '.');
        FOR i IN 2 .. (array_length(_domains, 1) -1) LOOP
            SELECT * INTO _domain FROM domain WHERE name=array_to_string(_domains[i:], '.') and tenant_customer_id=_host.tenant_customer_id;
            
            -- check host parent domain
            IF _domain.id IS NOT NULL THEN
                EXIT;
            END IF;
        END LOOP;
    END IF;

    RETURN _domain;
END;
$$ LANGUAGE plpgsql;


-- function: validate_host_parent_domain_customer()
-- description: validates if host and host parent domain belong to same customer
CREATE OR REPLACE FUNCTION validate_host_parent_domain_customer() RETURNS TRIGGER AS $$
DECLARE
    _host RECORD;
    _parent_domain RECORD;
BEGIN
    SELECT * INTO _host FROM host h WHERE h.id = NEW.host_id;

    _parent_domain=check_and_populate_host_parent_domain(_host);
    
    IF _parent_domain.id IS NULL THEN
        RAISE EXCEPTION 'Cannot update host ''%''; permission denied', _host.name;
    END IF;

    -- update order host
    UPDATE order_host SET name = _host.name, domain_id = _parent_domain.id WHERE id = NEW.new_host_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_host_object_unsupported()
-- description: check if tld supports host object
CREATE OR REPLACE FUNCTION order_prevent_if_host_object_unsupported() RETURNS TRIGGER AS $$
DECLARE
  v_host_object_supported  BOOLEAN;
BEGIN
    SELECT value INTO v_host_object_supported
    FROM v_attribute va
    JOIN order_host oh ON oh.id = NEW.new_host_id
    JOIN domain d ON d.id = oh.domain_id
    JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    WHERE va.key = 'tld.order.host_object_supported' AND 
            va.tld_name = vat.tld_name AND 
            va.tenant_id = vtc.tenant_id;

    IF NOT v_host_object_supported THEN
        RAISE EXCEPTION 'Host update not supported; use domain update on parent domain';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--
-- table: order_item_update_host
-- description: this table stores attributes of host related orders.
--
CREATE TABLE IF NOT EXISTS order_item_update_host (
  host_id UUID NOT NULL REFERENCES host,
  new_host_id UUID NOT NULL REFERENCES order_host,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

-- prevents order creation for non-existing host
DROP TRIGGER IF EXISTS a_order_prevent_if_host_does_not_exist_tg ON order_item_update_host;
CREATE TRIGGER a_order_prevent_if_host_does_not_exist_tg
  BEFORE INSERT ON order_item_update_host
  FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_host_does_not_exist();

-- make sure the initial status is 'pending'
DROP TRIGGER IF EXISTS order_item_force_initial_status_tg ON order_item_update_host;
CREATE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_update_host
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- validates if host and host parent domain belong to same customer
DROP TRIGGER IF EXISTS a_validate_host_parent_domain_customer_tg ON order_item_update_host;
CREATE TRIGGER a_validate_host_parent_domain_customer_tg
    BEFORE INSERT ON order_item_update_host 
    FOR EACH ROW EXECUTE PROCEDURE validate_host_parent_domain_customer();

-- prevents order creation if tld does not support host object
DROP TRIGGER IF EXISTS order_prevent_if_host_object_unsupported_tg ON order_item_update_host;
CREATE TRIGGER order_prevent_if_host_object_unsupported_tg
    BEFORE INSERT ON order_item_update_host 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_host_object_unsupported();

-- creates an execution plan for the item
DROP TRIGGER IF EXISTS a_order_item_update_plan_tg ON order_item_update_host;
CREATE TRIGGER a_order_item_update_plan_tg
    AFTER UPDATE ON order_item_update_host
    FOR EACH ROW WHEN ( 
      OLD.status_id <> NEW.status_id 
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    ) EXECUTE PROCEDURE plan_simple_order_item();

-- starts the execution of the order 
DROP TRIGGER IF EXISTS b_order_item_plan_start_tg ON order_item_update_host;
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_update_host
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
DROP TRIGGER IF EXISTS order_item_finish_tg ON order_item_update_host;
CREATE TRIGGER order_item_finish_tg
  AFTER UPDATE ON order_item_update_host
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_update_host(order_id);
CREATE INDEX ON order_item_update_host(status_id);




-- update host order views
-- v_order_update_host view
DROP VIEW IF EXISTS v_order_update_host;
CREATE OR REPLACE VIEW v_order_update_host AS
SELECT
    uh.id AS order_item_id,
    uh.order_id AS order_id,
    uh.host_id AS host_id,
    uh.new_host_id AS new_host_id,
    oh.name AS host_name,
    d.id AS domain_id,
    d.name AS domain_name,
    vat.accreditation_id,
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
    tc.name,
    oha.address
FROM order_item_update_host uh
    JOIN order_host oh ON oh.id = uh.new_host_id
    LEFT JOIN order_host_addr oha ON oha.host_id = oh.id
    JOIN domain d ON d.id = oh.domain_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN "order" o ON o.id=uh.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;


-- v_order_item_plan_object view
DROP VIEW IF EXISTS v_order_item_plan_object;
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
