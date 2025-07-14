ALTER TABLE IF EXISTS contact ADD  COLUMN IF NOT EXISTS metadata jsonb;

ALTER TABLE IF EXISTS contact DROP COLUMN IF EXISTS customer_contact_ref;

CREATE INDEX IF NOT EXISTS contact_metadata_idx  ON contact USING GIN(metadata);

------------------------------------------------------------------------------------------------
-- function: jsonb_get_contact_by_id()
-- description: returns a jsonb containing all the attributes of a contact
--

CREATE OR REPLACE FUNCTION jsonb_get_contact_by_id(p_id UUID) RETURNS JSONB AS $$
BEGIN
    RETURN
        ( -- The basic attributes of a contact, from the contact table, plus the contact_type.name
            SELECT to_jsonb(c) AS basic_attr
            FROM (
                SELECT id, tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, fax, country, language, tags, documentation, metadata
                FROM ONLY contact WHERE
                id = p_id
            ) c
        )
        ||
        COALESCE(
        ( -- The additional attributes of a contact, from the contact_attribute table
            SELECT jsonb_object_agg(an.name, ca.value) AS extended_attr
            FROM ONLY contact_attribute ca
            JOIN attribute an ON an.id=ca.attribute_id
            WHERE ca.contact_id = p_id
            GROUP BY ca.contact_id
        )
        , '{}'::JSONB)
        ||
        ( -- The postal info of a contact as an object holding the array sorting the UTF-8 representation before the ASCII-only representation
            SELECT to_jsonb(cpa)
            FROM (
                SELECT jsonb_agg(cp) AS contact_postals
                FROM (
                    SELECT is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
                    FROM ONLY contact_postal
                    WHERE contact_id = p_id
                    ORDER BY is_international ASC
                ) cp
            ) cpa
        );
END;
$$ LANGUAGE plpgsql STABLE;


--------------------------------------------------------------------------------------------------------
-- function: jsonb_get_order_contact_by_id()
-- description: returns a jsonb containing all the attributes of an order contact
--

CREATE OR REPLACE FUNCTION jsonb_get_order_contact_by_id(p_id UUID) RETURNS JSONB AS $$
BEGIN
    RETURN
        ( -- The basic attributes of a contact, from the contact table, plus the contact_type.name
            SELECT to_jsonb(c) AS basic_attr
            FROM (
                     SELECT id, tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, fax, country, language, tags, documentation, metadata
                     FROM ONLY order_contact WHERE
                         id = p_id
                 ) c
        )
        ||
        COALESCE(
                ( -- The additional attributes of a contact, from the contact_attribute table
                    SELECT jsonb_object_agg(an.name, ca.value) AS extended_attr
                    FROM ONLY order_contact_attribute ca
                             JOIN attribute an ON an.id=ca.attribute_id
                    WHERE ca.contact_id = p_id
                    GROUP BY ca.contact_id
                )
            , '{}'::JSONB)
        ||
        ( -- The postal info of a contact as an object holding the array sorting the UTF-8 representation before the ASCII-only representation
            SELECT to_jsonb(cpa)
            FROM (
                     SELECT jsonb_agg(cp) AS contact_postals
                     FROM (
                              SELECT is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
                              FROM ONLY order_contact_postal
                              WHERE contact_id = p_id
                              ORDER BY is_international ASC
                          ) cp
                 ) cpa
        );
END;
$$ LANGUAGE plpgsql STABLE;

---------------------------------------------------------------------------------------------------------------
-- function: update_contact_using_order_contact()
-- description: updates contact and details using order contact
--

CREATE OR REPLACE FUNCTION update_contact_using_order_contact(c_id UUID, oc_id UUID) RETURNS void AS $$
BEGIN
    -- update contact
    UPDATE
        contact c
    SET
        type_id = oc.type_id,
        title = oc.title,
        org_reg = oc.org_reg,
        org_vat = oc.org_vat,
        org_duns = oc.org_duns,
        email = oc.email,
        phone = oc.phone,
        fax = oc.fax,
        country = oc.country,
        language = oc.language,        
        tags = oc.tags,
        documentation = oc.documentation,
        metadata = oc.metadata
    FROM
        order_contact oc
    WHERE
        c.id = c_id AND oc.id = oc_id;

    -- update contact_postal
    UPDATE
        contact_postal cp
    SET
        is_international=ocp.is_international,
        first_name=ocp.first_name,
        last_name=ocp.last_name,
        org_name=ocp.org_name,
        address1=ocp.address1,
        address2=ocp.address2,
        address3=ocp.address3,
        city=ocp.city,
        postal_code=ocp.postal_code,
        state=ocp.state
    FROM
        order_contact_postal ocp
    WHERE
        ocp.contact_id = oc_id AND
        cp.contact_id = c_id AND
        cp.is_international = ocp.is_international;

    -- update contact_attribute
    UPDATE
        contact_attribute ca
    SET
        value=oca.value
    FROM order_contact_attribute oca
    WHERE
        oca.contact_id = oc_id AND
        ca.contact_id = c_id AND
        ca.attribute_id = oca.attribute_id AND
        ca.attribute_type_id = oca.attribute_type_id;

END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------
--
-- function: duplicate_contact_by_id()
-- description: create new contact and details from existing contact
--
CREATE OR REPLACE FUNCTION duplicate_contact_by_id(c_id UUID) RETURNS UUID AS $$
DECLARE
    _contact_id     UUID;
BEGIN
    -- create new contact
    WITH c_id AS (
        INSERT INTO contact(
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
                "language",                
                tags,
                documentation,
                metadata
            )
            SELECT
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
                "language",                
                tags,
                documentation,
                metadata
            FROM
                ONLY contact
            WHERE
                id = c_id
            RETURNING
                id
    )
    SELECT
        * INTO _contact_id
    FROM
        c_id;

    INSERT INTO contact_postal(
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
    SELECT
        _contact_id,
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
    FROM
        ONLY contact_postal
    WHERE
        contact_id = c_id;

    INSERT INTO contact_attribute(contact_id, attribute_id, attribute_type_id, value)
    SELECT
        _contact_id,
        attribute_id,
        attribute_type_id,
        value
    FROM
        ONLY contact_attribute
    WHERE
        contact_id = c_id;

    RETURN _contact_id;

END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------------------------------------------

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

------------------------------------------------------------------------------------------------
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

