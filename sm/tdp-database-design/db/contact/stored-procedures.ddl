--
-- function: jsonb_get_rdp_contact_by_id()
-- description: returns a jsonb containing all the attributes of a contact filtered according to allowed data elements
--
CREATE OR REPLACE FUNCTION jsonb_select_contact_data_by_id(
    p_id UUID,
    selected_elements TEXT[] DEFAULT '{}'
) RETURNS JSONB AS $$
DECLARE
    result JSONB;
    attr_result JSONB;
    postal_result JSONB;
BEGIN
    SELECT jsonb_build_object(
                   'id', c.id,
                   'short_id', c.short_id,
                   'contact_type', tc_name_from_id('contact_type', c.type_id),
                   'title', CASE WHEN 'title' = ANY(selected_elements) THEN c.title END,
                   'org_reg', CASE WHEN 'org_reg' = ANY(selected_elements) THEN c.org_reg END,
                   'org_vat', CASE WHEN 'org_vat' = ANY(selected_elements) THEN c.org_vat END,
                   'org_duns', CASE WHEN 'org_duns' = ANY(selected_elements) THEN c.org_duns END,
                   'tenant_customer_id', CASE WHEN 'tenant_customer_id' = ANY(selected_elements) THEN c.tenant_customer_id END,
                   'email', CASE WHEN 'email' = ANY(selected_elements) THEN c.email END,
                   'phone', CASE WHEN 'phone' = ANY(selected_elements) THEN c.phone END,
                   'phone_ext', CASE WHEN 'phone_ext' = ANY(selected_elements) THEN c.phone_ext END,
                   'fax', CASE WHEN 'fax' = ANY(selected_elements) THEN c.fax END,
                   'fax_ext', CASE WHEN 'fax_ext' = ANY(selected_elements) THEN c.fax_ext END,
                   'country', CASE WHEN 'country' = ANY(selected_elements) THEN c.country END,
                   'language', CASE WHEN 'language' = ANY(selected_elements) THEN c.language END,
                   'documentation', CASE WHEN 'documentation' = ANY(selected_elements) THEN c.documentation END,
                   'tags', c.tags,
                   'metadata', c.metadata
           ) INTO result
    FROM ONLY contact c
    WHERE c.id = p_id;

    -- Skip further processing if contact not found
    IF result IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT jsonb_object_agg(
                   an.name,
                   CASE WHEN an.name = ANY(selected_elements) THEN ca.value END
           ) INTO attr_result
    FROM ONLY contact_attribute ca
             JOIN attribute an ON an.id = ca.attribute_id
    WHERE ca.contact_id = p_id;

    -- Get postal data with direct filtering
    SELECT jsonb_build_object('contact_postals', jsonb_agg(
            jsonb_build_object(
                    'is_international', cp.is_international,
                    'first_name', CASE WHEN 'first_name' = ANY(selected_elements) THEN cp.first_name END,
                    'last_name', CASE WHEN 'last_name' = ANY(selected_elements) THEN cp.last_name END,
                    'org_name', CASE WHEN 'org_name' = ANY(selected_elements) THEN cp.org_name END,
                    'address1', CASE WHEN 'address1' = ANY(selected_elements) THEN cp.address1 END,
                    'address2', CASE WHEN 'address2' = ANY(selected_elements) THEN cp.address2 END,
                    'address3', CASE WHEN 'address3' = ANY(selected_elements) THEN cp.address3 END,
                    'city', CASE WHEN 'city' = ANY(selected_elements) THEN cp.city END,
                    'postal_code', CASE WHEN 'postal_code' = ANY(selected_elements) THEN cp.postal_code END,
                    'state', CASE WHEN 'state' = ANY(selected_elements) THEN cp.state END
            ) ORDER BY cp.is_international ASC
                                                 )) INTO postal_result
    FROM ONLY contact_postal cp
    WHERE cp.contact_id = p_id;

    -- Combine results
    RETURN result || COALESCE(attr_result, '{}'::JSONB) || COALESCE(postal_result, '{}'::JSONB);
END;
$$ LANGUAGE plpgsql STABLE;

--
-- function: jsonb_get_contact_by_id()
-- description: returns a jsonb containing all the attributes of a contact
--

CREATE OR REPLACE FUNCTION jsonb_get_contact_by_id(p_id UUID) RETURNS JSONB AS $$
BEGIN
    RETURN
        ( -- The basic attributes of a contact, from the contact table, plus the contact_type.name
            SELECT to_jsonb(c) AS basic_attr
            FROM (
                SELECT id, short_id, tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, language, tags, documentation, metadata
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

--
-- function: jsonb_get_order_contact_by_id()
-- description: returns a jsonb containing all the attributes of an order contact
--

CREATE OR REPLACE FUNCTION jsonb_get_order_contact_by_id(p_id UUID) RETURNS JSONB AS $$
BEGIN
    RETURN
        ( -- The basic attributes of a contact, from the contact table, plus the contact_type.name
            SELECT to_jsonb(c) AS basic_attr
            FROM (
                     SELECT id, tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, language, tags, documentation, metadata
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


--
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
        phone_ext = oc.phone_ext,
        fax = oc.fax,
        fax_ext = oc.fax_ext,
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
        cp.contact_id = c_id;

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
                phone_ext,
                fax,
                fax_ext,
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
                phone_ext,
                fax,
                fax_ext,
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

CREATE OR REPLACE FUNCTION delete_contact(delete_contact_id uuid) RETURNS VOID AS $$
BEGIN
    DELETE FROM ONLY contact_attribute where contact_id=delete_contact_id;
    DELETE FROM ONLY contact_postal where contact_id=delete_contact_id;
    DELETE FROM ONLY contact where id=delete_contact_id;
END;
$$ LANGUAGE plpgsql;


-- function: gen_short_id()
-- description: This function generates a unique, random string of length 16 characters
-- using a subset of alphanumeric characters and some special characters.
CREATE OR REPLACE FUNCTION gen_short_id() RETURNS TEXT AS $$
DECLARE
    allowed_chars text := '0123456789abcdefghijklmnopqrstuvwxyz';
    result text := '';
    bytes bytea := gen_random_bytes(32);
    i int := 0;
BEGIN
    FOR i IN 1..16 LOOP
            -- Concatenate a character from 'allowed_chars' based on the current byte.
            -- 'get_byte' function extracts the byte at position 'i' from 'bytes'.
            -- 'substr' function selects a character from 'allowed_chars' based on the byte value.
            result := result || substr(allowed_chars, (get_byte(bytes, i) % length(allowed_chars)) + 1, 1);
        END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;
