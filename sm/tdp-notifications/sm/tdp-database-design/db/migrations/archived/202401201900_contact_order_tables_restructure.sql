--As we don't have product data - this is a data loss migration for  a order contact creation.

DROP VIEW IF EXISTS v_order_create_contact;
DROP TABLE IF EXISTS order_item_create_contact_postal;
DROP TABLE IF EXISTS order_item_create_contact_attribute;
---------------------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_order_item_plan_object;
ALTER TABLE IF EXISTS  create_contact_plan
DROP CONSTRAINT IF EXISTS create_contact_plan_order_item_id_fkey;
DROP TABLE IF EXISTS order_item_create_contact;
----------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS  order_item_create_contact (
  contact_id UUID NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status,  
  FOREIGN KEY (contact_id) REFERENCES order_contact
) INHERITS (order_item,class.audit_trail);

-- make sure the initial status is 'pending'
CREATE OR REPLACE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_create_contact 
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- creates an execution plan for the item
CREATE OR REPLACE TRIGGER a_order_item_create_plan_tg
    AFTER UPDATE ON order_item_create_contact 
    FOR EACH ROW WHEN ( 
      OLD.status_id <> NEW.status_id 
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    )EXECUTE PROCEDURE plan_simple_order_item();

-- starts the execution of the order 
CREATE OR REPLACE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_create_contact 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE OR REPLACE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_create_contact
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_create_contact(order_id);
CREATE INDEX ON order_item_create_contact(status_id);
-----------------------------------------------------------------------------
TRUNCATE TABLE create_contact_plan;
ALTER TABLE IF EXISTS  create_contact_plan
DROP CONSTRAINT IF EXISTS create_contact_plan_order_item_id_fkey,
ADD CONSTRAINT  create_contact_plan_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES order_item_create_contact;

-----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS  order_contact_attribute(
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

-----------------------------------------------------------------------------
--
-- function: create_contact_order_from_jsonb()
-- description: Parses a JSONB into the tables order, order_item_create_contact, order_contact, order_contact_postal, order_contact_attribute
--

CREATE OR REPLACE FUNCTION create_contact_order_from_jsonb(p_js JSONB) RETURNS UUID AS $$
DECLARE
    _order_id UUID;
    _order_contact_id UUID;
    _order_item_create_contact_id UUID;
    _postal_js JSONB;
    _attr_id UUID;
    _attr_name TEXT;
BEGIN
    -- Store the order attributes and return the order id
    INSERT INTO "order"(
      tenant_customer_id,
      type_id,
      customer_user_id
    )
    VALUES(
      (p_js->>'tenant_customer_id')::UUID,
      (SELECT id FROM v_order_type WHERE name='create' AND product_name='contact'),
      (p_js->>'customer_user_id')::UUID
    ) RETURNING id INTO _order_id;

     -- Store the basic contact attributes
    INSERT INTO order_contact(
      order_id,
      type_id,
      title,
      org_reg,
      org_vat,
      org_duns,
      tenant_customer_id,
      email,
      phone,
      fax,
      country,
      language,
      customer_contact_ref,
      tags,
      documentation
    )
    VALUES(
      _order_id,
      tc_id_from_name('contact_type',p_js->>'contact_type'),
      p_js->>'title',
      p_js->>'org_reg',
      p_js->>'org_vat',
      p_js->>'org_duns',
      (p_js->>'tenant_customer_id')::UUID,
      p_js->>'email',
      p_js->>'phone',
      p_js->>'fax',
      p_js->>'country',
      p_js->>'language',
      p_js->>'customer_contact_ref',
      jsonb_array_to_text_array(p_js->'tags'),
      jsonb_array_to_text_array(p_js->'documentation')
    ) RETURNING id INTO _order_contact_id;

    -- Store the order_item_create_contact 
    INSERT INTO order_item_create_contact(
      order_id, 
      contact_id
    )
    VALUES(
      _order_id,
      _order_contact_id      
    ) RETURNING id INTO _order_item_create_contact_id;

    -- store postal attributes
    FOR _postal_js IN SELECT jsonb_array_elements(p_js->'order_contact_postals')
    LOOP
      INSERT INTO order_contact_postal(
        contact_id,
        is_international,
        first_name,
        last_name,
        org_name,
        address1,
        address2,
        address3,
        city,
        postal_code,
        state
      )
      VALUES(
        _order_contact_id,
        (_postal_js->>'is_international')::BOOLEAN,
        _postal_js->>'first_name',
        _postal_js->>'last_name',
        _postal_js->>'org_name',
        _postal_js->>'address1',
        _postal_js->>'address2',
        _postal_js->>'address3',
        _postal_js->>'city',
        _postal_js->>'postal_code',
        _postal_js->>'state'
      );
    END LOOP;

    -- store additional attributes
    FOR _attr_id,_attr_name IN SELECT a.id,a.name FROM attribute a JOIN attribute_type at ON at.id=a.type_id AND at.name='contact' 
    LOOP
      IF NOT p_js->>_attr_name IS NULL THEN
        INSERT INTO order_contact_attribute(
          attribute_id,
          contact_id,
          value
        )
        VALUES(
          _attr_id,
          _order_contact_id,
          p_js->>_attr_name
        );
      END IF;
    END LOOP;

    RETURN _order_id;
END;
$$ LANGUAGE plpgsql;
------------------------------------------------------------------------------

--
-- function: jsonb_get_create_contact_order_by_id()
-- description: returns a jsonb containing all the attributes of a contact
--

CREATE OR REPLACE FUNCTION jsonb_get_create_contact_order_by_id(p_id UUID) RETURNS JSONB AS $$
DECLARE
  _order_item_create_contact_id UUID;
  _order_contact_id UUID;
BEGIN
  SELECT id,contact_id INTO STRICT _order_item_create_contact_id,_order_contact_id
    FROM order_item_create_contact
    WHERE order_id = p_id;

  RETURN
    ( -- The basic attributes of a create contact order, from the order item create contact table, plus the contact_type.name
      SELECT to_jsonb(oicc) AS basic_attr
      FROM (
        SELECT tc_name_from_id('contact_type',type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, fax, country, language, customer_contact_ref, tags, documentation
        FROM order_item_create_contact cc
        JOIN order_contact oc on oc.id = cc.contact_id
        WHERE cc.id = _order_item_create_contact_id
      ) oicc
    )
    ||
    COALESCE(
    ( -- The additional attributes of a create contact order, from the order_contact_attribute table
      SELECT jsonb_object_agg(a.name, oca.value) AS extended_attr
      FROM order_contact_attribute oca      
      JOIN attribute a ON a.id=oca.attribute_id
      WHERE oca.contact_id = _order_contact_id
      GROUP BY oca.contact_id
    ),
    '{}'::JSONB)
    ||
    ( -- The contact postals of a create contact order as an object holding the array sorting the UTF-8 representation before the ASCII-only representation
      SELECT to_jsonb(ocpa)
      FROM (
        SELECT jsonb_agg(ocp) AS order_contact_postals
        FROM (
          SELECT is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
          FROM order_contact_postal
          WHERE contact_id = _order_contact_id
          ORDER BY is_international ASC
        ) ocp
      ) ocpa
    )
    ||
    ( -- The basic order attributes
      SELECT to_jsonb(o) AS order_attr
      FROM (
        SELECT id, created_date, updated_date, tenant_customer_id, customer_user_id,
          (SELECT to_jsonb(ot) AS type FROM (SELECT tc_name_from_id('v_order_type',type_id) AS name) ot),
          (SELECT to_jsonb(os) AS status FROM (SELECT tc_name_from_id('order_status',status_id) AS name) os)
        FROM "order"
        WHERE id = p_id
      ) o
    );
END;
$$ LANGUAGE plpgsql STABLE;

------------------------------------------------------------------------------------------------

-- function: plan_create_contact_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_contact_provision_contact() RETURNS TRIGGER AS $$
DECLARE
---  v_contact_id     UUID;
  v_create_contact   RECORD;
BEGIN

  -- thanks to the magic from inheritance, the contact table already
  -- contains the data, we just need to materialize it there.
  INSERT INTO contact (SELECT c.* FROM contact c JOIN order_item_create_contact oicc ON  c.id = oicc.contact_id  WHERE oicc.id = NEW.reference_id);    
  INSERT INTO contact_postal (SELECT cp.* FROM contact_postal cp JOIN order_item_create_contact oicc ON  cp.contact_id = oicc.contact_id  WHERE oicc.id = NEW.reference_id);    
  INSERT INTO contact_attribute (SELECT ca.* FROM contact_attribute ca JOIN order_item_create_contact oicc ON  ca.contact_id = oicc.contact_id  WHERE oicc.id = NEW.reference_id);    

  -- complete the order item
  UPDATE create_contact_plan 
    SET status_id = tc_id_from_name('order_item_plan_status','completed')
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_order_create_contact AS 
SELECT 
    cc.id AS order_item_id,
    cc.order_id AS order_id,
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
FROM order_item_create_contact cc
    JOIN order_contact oc ON oc.id = cc.contact_id
    JOIN contact_type ct ON ct.id = oc.type_id    
    JOIN order_contact_postal cp ON cp.contact_id = oc.id AND NOT cp.is_international
    JOIN "order" o ON o.id=cc.order_id  
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id;
-----------------------------------------------------------------------------
   
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
;


