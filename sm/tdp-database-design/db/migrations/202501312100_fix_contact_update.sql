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
