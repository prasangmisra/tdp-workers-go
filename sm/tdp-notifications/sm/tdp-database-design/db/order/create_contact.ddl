
--
-- table: order_item_create_contact
-- description: this table stores attributes of contact related orders.
--

CREATE TABLE order_item_create_contact (
  contact_id UUID NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status,  
  FOREIGN KEY (contact_id) REFERENCES order_contact
) INHERITS (order_item,class.audit_trail);

-- make sure the initial status is 'pending'
CREATE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_create_contact 
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_create_plan_tg
    AFTER UPDATE ON order_item_create_contact 
    FOR EACH ROW WHEN ( 
      OLD.status_id <> NEW.status_id 
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    )EXECUTE PROCEDURE plan_simple_order_item();

-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_create_contact 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_create_contact
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_create_contact(order_id);
CREATE INDEX ON order_item_create_contact(status_id);

-- this table contains the plan for creating a contact
CREATE TABLE create_contact_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_create_contact
) INHERITS(order_item_plan,class.audit_trail);

CREATE TRIGGER plan_create_contact_provision_contact_tg 
  AFTER UPDATE ON create_contact_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','contact') 
  )
  EXECUTE PROCEDURE plan_create_contact_provision_contact();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_contact_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON create_contact_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();  


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

--
-- function: jsonb_get_order_by_id()
-- description: returns product_name and jsonb containing all the attributes of order for the product
--

CREATE OR REPLACE FUNCTION jsonb_get_order_by_id(IN p_id UUID, OUT product_name text, OUT order_data JSONB) AS $$
BEGIN
  SELECT vot.product_name INTO product_name
    FROM v_order_type vot 
    JOIN "order" o ON o.type_id = vot.id
    WHERE o.id = p_id;

  IF product_name = 'contact' THEN
    order_data := jsonb_get_create_contact_order_by_id(p_id);
  ELSIF product_name = 'host' THEN
    order_data := jsonb_get_create_host_order_by_id(p_id);
  ELSE
    RAISE EXCEPTION 'unsupported order product name %', product_name;
  END IF;

END;
$$ LANGUAGE plpgsql STABLE;

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
        SELECT tc_name_from_id('contact_type',type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, fax, country, language, tags, documentation, metadata
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
