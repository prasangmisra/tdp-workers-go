ALTER TABLE IF EXISTS contact
    ADD COLUMN IF NOT EXISTS phone_ext text,
    ADD COLUMN IF NOT EXISTS fax_ext text;


ALTER TABLE IF EXISTS history.contact
    ADD COLUMN IF NOT EXISTS phone_ext text,
    ADD COLUMN IF NOT EXISTS fax_ext text;

CREATE OR REPLACE FUNCTION jsonb_select_contact_data_by_id(
    p_id uuid, 
    selected_elements text[] DEFAULT '{}'
) RETURNS jsonb AS $$
DECLARE
    result jsonb;
    attr_result jsonb;
    postal_result jsonb;
BEGIN
    SELECT
        jsonb_build_object(
            'id', c.id, 
            'short_id', c.short_id, 
            'contact_type', tc_name_from_id('contact_type', c.type_id), 
            'title', CASE WHEN 'title' = ANY (selected_elements) THEN c.title END, 
            'org_reg', CASE WHEN 'org_reg' = ANY (selected_elements) THEN c.org_reg END, 
            'org_vat', CASE WHEN 'org_vat' = ANY (selected_elements) THEN c.org_vat END, 
            'org_duns', CASE WHEN 'org_duns' = ANY (selected_elements) THEN c.org_duns END, 
            'tenant_customer_id', CASE WHEN 'tenant_customer_id' = ANY (selected_elements) THEN c.tenant_customer_id END, 
            'email', CASE WHEN 'email' = ANY (selected_elements) THEN c.email END, 
            'phone', CASE WHEN 'phone' = ANY (selected_elements) THEN c.phone END, 
            'phone_ext', CASE WHEN 'phone_ext' = ANY (selected_elements) THEN c.phone_ext END, 
            'fax', CASE WHEN 'fax' = ANY (selected_elements) THEN c.fax END, 
            'fax_ext', CASE WHEN 'fax_ext' = ANY (selected_elements) THEN c.fax_ext END, 
            'country', CASE WHEN 'country' = ANY (selected_elements) THEN c.country END, 
            'language', CASE WHEN 'language' = ANY (selected_elements) THEN c.language END, 
            'documentation', CASE WHEN 'documentation' = ANY (selected_elements) THEN c.documentation END, 
            'tags', c.tags, 
            'metadata', c.metadata
            ) INTO result
    FROM ONLY contact c
    WHERE c.id = p_id;

    IF result IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT
        jsonb_object_agg(
            an.name, 
            CASE WHEN an.name = ANY (selected_elements) THEN ca.value END
            ) INTO attr_result
    FROM ONLY contact_attribute ca
    JOIN attribute an ON an.id = ca.attribute_id
    WHERE ca.contact_id = p_id;

    SELECT
        jsonb_build_object('contact_postals', jsonb_agg(
            jsonb_build_object(
                'is_international', cp.is_international, 
                'first_name', CASE WHEN 'first_name' = ANY (selected_elements) THEN cp.first_name END, 
                'last_name', CASE WHEN 'last_name' = ANY (selected_elements) THEN cp.last_name END, 
                'org_name', CASE WHEN 'org_name' = ANY (selected_elements) THEN cp.org_name END, 
                'address1', CASE WHEN 'address1' = ANY (selected_elements) THEN cp.address1 END, 
                'address2', CASE WHEN 'address2' = ANY (selected_elements) THEN cp.address2 END, 
                'address3', CASE WHEN 'address3' = ANY (selected_elements) THEN cp.address3 END, 
                'city', CASE WHEN 'city' = ANY (selected_elements) THEN cp.city END, 
                'postal_code', CASE WHEN 'postal_code' = ANY (selected_elements) THEN cp.postal_code END, 
                'state', CASE WHEN 'state' = ANY (selected_elements) THEN cp.state END
                ) ORDER BY cp.is_international ASC
                )) INTO postal_result
    FROM ONLY contact_postal cp
    WHERE cp.contact_id = p_id;

    RETURN result || COALESCE(attr_result, '{}'::jsonb) || COALESCE(postal_result, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION jsonb_get_contact_by_id(p_id uuid) RETURNS jsonb AS $$
BEGIN
    RETURN(
        SELECT
            to_jsonb(c) AS basic_attr
        FROM(
            SELECT id, short_id, tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, language, tags, documentation, metadata
            FROM ONLY contact WHERE
                id = p_id
            ) c
        ) 
        || 
        COALESCE(
        (
        SELECT jsonb_object_agg(an.name, ca.value) AS extended_attr
        FROM ONLY contact_attribute ca
        JOIN attribute an ON an.id = ca.attribute_id
        WHERE ca.contact_id = p_id 
        GROUP BY ca.contact_id
        ), '{}'::JSONB) 
        ||
        (
        SELECT to_jsonb(cpa)
        FROM (
            SELECT jsonb_agg(cp) AS contact_postals
            FROM(
                SELECT is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
                FROM ONLY contact_postal
                WHERE contact_id = p_id
                ORDER BY is_international ASC
            ) cp
        ) cpa
    );
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION jsonb_get_order_contact_by_id(p_id uuid) RETURNS jsonb AS $$
BEGIN
    RETURN(
        SELECT to_jsonb(c) AS basic_attr
        FROM(
            SELECT id, tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, LANGUAGE, tags, documentation, metadata
            FROM ONLY order_contact
            WHERE id = p_id
            ) c
        ) 
        || 
        COALESCE(
            (
        SELECT jsonb_object_agg(an.name, ca.value) AS extended_attr 
        FROM ONLY order_contact_attribute ca
            JOIN attribute an ON an.id = ca.attribute_id
        WHERE ca.contact_id = p_id 
        GROUP BY ca.contact_id
        )
        , '{}'::JSONB) 
        ||
        (
        SELECT to_jsonb(cpa)
        FROM (
            SELECT jsonb_agg(cp) AS contact_postals
            FROM(
                SELECT is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
                FROM ONLY order_contact_postal
                WHERE contact_id = p_id
                ORDER BY is_international ASC
            ) cp
        ) cpa
    );
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION update_contact_using_order_contact(c_id uuid, oc_id uuid) RETURNS void AS $$
BEGIN
    UPDATE contact c
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
    FROM order_contact oc
    WHERE c.id = c_id AND oc.id = oc_id;

    UPDATE contact_postal cp
    SET
        is_international = ocp.is_international,
        first_name = ocp.first_name,
        last_name = ocp.last_name,
        org_name = ocp.org_name,
        address1 = ocp.address1,
        address2 = ocp.address2,
        address3 = ocp.address3,
        city = ocp.city,
        postal_code = ocp.postal_code,
        state = ocp.state
    FROM order_contact_postal ocp
    WHERE ocp.contact_id = oc_id AND cp.contact_id = c_id;

    UPDATE contact_attribute ca
    SET value = oca.value
    FROM order_contact_attribute oca
    WHERE oca.contact_id = oc_id AND ca.contact_id = c_id
          AND ca.attribute_id = oca.attribute_id
          AND ca.attribute_type_id = oca.attribute_type_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION duplicate_contact_by_id(c_id uuid)
    RETURNS uuid
    AS $$
DECLARE
    _contact_id uuid;
BEGIN
    WITH c_id AS (
INSERT INTO contact(type_id, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, language, tags, documentation, metadata)
        SELECT type_id, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, LANGUAGE, tags, documentation, metadata
        FROM ONLY contact
        WHERE id = c_id
        RETURNING id
)
    SELECT
        * INTO _contact_id
    FROM
        c_id;
    INSERT INTO contact_postal(contact_id, is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state)
    SELECT _contact_id, is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
    FROM ONLY contact_postal
    WHERE contact_id = c_id;
    INSERT INTO contact_attribute(contact_id, attribute_id, attribute_type_id, value)
    SELECT _contact_id, attribute_id, attribute_type_id, value
    FROM ONLY contact_attribute
    WHERE contact_id = c_id;
    RETURN _contact_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_domain_with_reason(_domain_id uuid, _reason text)
    RETURNS void
    AS $$
BEGIN
    IF _reason IS NULL THEN
        RAISE EXCEPTION 'No reason provided for domain deletion';
    END IF;
    -- 1. add record to history.domain table
    INSERT INTO history.domain(reason, id, tenant_customer_id, tenant_name, customer_name, accreditation_tld_id, name, auth_info, roid, ry_created_date, ry_expiry_date, ry_updated_date, ry_transfered_date, deleted_date, expiry_date, auto_renew, secdns_max_sig_life, tags, metadata, uname, language, migration_info)
    SELECT _reason, d.id, d.tenant_customer_id, vtc.tenant_name, vtc.name AS customer_name, d.accreditation_tld_id, d.name, d.auth_info, d.roid, d.ry_created_date, d.ry_expiry_date, d.ry_updated_date, d.ry_transfered_date, d.deleted_date, d.expiry_date, d.auto_renew, d.secdns_max_sig_life, d.tags, d.metadata, d.uname, d.language, d.migration_info
    FROM
        DOMAIN d
        JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
    WHERE
        d.id = _domain_id;
    -- 2. add record to contact
    WITH history_contact AS(
INSERT INTO history.contact(orig_id, type_id, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, language, tags, documentation, short_id, metadata, migration_info)
        SELECT DISTINCT ON(c.id) c.id, c.type_id, c.title, c.org_reg, c.org_vat, c.org_duns, c.tenant_customer_id, c.email, c.phone, c.phone_ext, c.fax, c.fax_ext, c.country, c.language, c.tags, c.documentation, c.short_id, c.metadata, c.migration_info
        FROM
            domain_contact dc
            JOIN ONLY contact c ON c.id = dc.contact_id
        WHERE
            dc.domain_id = _domain_id
        RETURNING
            id,
            orig_id
),
history_contact_postal AS(
INSERT INTO history.contact_postal(orig_id, contact_id, is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state)
    SELECT cp.id, hc.id, cp.is_international, cp.first_name, cp.last_name, cp.org_name, cp.address1, cp.address2, cp.address3, cp.city, cp.postal_code, cp.state
    FROM
        ONLY contact_postal cp
        JOIN history_contact hc ON hc.orig_id = cp.contact_id
),
history_contact_attribute AS(
INSERT INTO history.contact_attribute(attribute_id, attribute_type_id, contact_id, value)
    SELECT ca.attribute_id, ca.attribute_type_id, hc.id, ca.value
    FROM
        ONLY contact_attribute ca
        JOIN history_contact hc ON hc.orig_id = ca.contact_id)
    INSERT INTO history.domain_contact(domain_id, contact_id, domain_contact_type_id, handle, is_local_presence, is_privacy_proxy, is_private)
    SELECT dc.domain_id, hc.id, dc.domain_contact_type_id, dc.handle, dc.is_local_presence, dc.is_privacy_proxy, dc.is_private
    FROM domain_contact dc
    JOIN history_contact hc ON hc.orig_id = dc.contact_id
    WHERE
        dc.domain_id = _domain_id;
    -- 3. add record to host
    WITH history_host AS(
INSERT INTO history.host(orig_id, tenant_customer_id, name, domain_id, tags, metadata)
        SELECT h.id, h.tenant_customer_id, h.name, h.domain_id, h.tags, h.metadata
        FROM
            domain_host dh
            JOIN ONLY host h ON h.id = dh.host_id
        WHERE
            dh.domain_id = _domain_id
        RETURNING
            id,
            orig_id
),
history_host_addr AS(
INSERT INTO history.host_addr(host_id, address)
    SELECT
        hh.id,
        ha.address
    FROM
        ONLY host_addr ha
        JOIN history_host hh ON hh.orig_id = ha.host_id)
    INSERT INTO history.domain_host(domain_id, host_id)
    SELECT
        _domain_id,
        hh.id
    FROM
        history_host hh;
    -- 4. add record to dns
    WITH history_secdns_ds_key_data AS(
INSERT INTO history.secdns_key_data(orig_id, flags, protocol, algorithm, public_key)
        SELECT skd.id, skd.flags, skd.protocol, skd.algorithm, skd.public_key
        FROM
            domain_secdns ds
            JOIN ONLY secdns_ds_data sdd ON sdd.id = ds.ds_data_id
            JOIN ONLY secdns_key_data skd ON skd.id = sdd.key_data_id
        WHERE
            ds.domain_id = _domain_id
            AND ds.ds_data_id IS NOT NULL
        RETURNING
            id,
            orig_id
),
history_secdns_ds_data AS(
INSERT INTO history.secdns_ds_data(orig_id, key_tag, algorithm, digest_type, digest, key_data_id)
    SELECT sdd.id, sdd.key_tag, sdd.algorithm, sdd.digest_type, sdd.digest, hsdkd.id
    FROM
        domain_secdns ds
        JOIN ONLY secdns_ds_data sdd ON sdd.id = ds.ds_data_id
        LEFT JOIN history_secdns_ds_key_data hsdkd ON hsdkd.orig_id = sdd.key_data_id
    WHERE
        ds.domain_id = _domain_id
        AND ds.ds_data_id IS NOT NULL
    RETURNING
        id
),
history_secdns_key_data AS(
INSERT INTO history.secdns_key_data(orig_id, flags, protocol, algorithm, public_key)
    SELECT skd.id, skd.flags, skd.protocol, skd.algorithm, skd.public_key
    FROM
        domain_secdns ds
        JOIN ONLY secdns_key_data skd ON skd.id = ds.key_data_id
    WHERE
        ds.domain_id = _domain_id
        AND ds.key_data_id IS NOT NULL
    RETURNING
        id)
INSERT INTO history.domain_secdns(domain_id, ds_data_id, key_data_id)
SELECT
    _domain_id,
    hsdd.id,
    NULL
FROM
    history_secdns_ds_data hsdd
UNION
SELECT
    _domain_id,
    NULL,
    hskd.id
FROM
    history_secdns_key_data hskd;
    -- 5 delete decord from domain; information will be deleted on cascade from related 8 tables;
    DELETE FROM DOMAIN
    WHERE domain.id = _domain_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_contact_order_from_jsonb(p_js jsonb)
    RETURNS uuid
    AS $$
DECLARE
    _order_id uuid;
    _order_contact_id uuid;
    _order_item_create_contact_id uuid;
    _postal_js jsonb;
    _attr_id uuid;
    _attr_name text;
BEGIN
    -- Store the order attributes and return the order id
    INSERT INTO "order"(tenant_customer_id, type_id, customer_user_id)
        VALUES ((p_js ->> 'tenant_customer_id')::uuid,(
                SELECT
                    id
                FROM
                    v_order_type
                WHERE
                    name = 'create'
                    AND product_name = 'contact'),
(p_js ->> 'customer_user_id')::uuid)
    RETURNING
        id INTO _order_id;
    -- Store the basic contact attributes
    INSERT INTO order_contact(order_id, type_id, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, language, tags, documentation)
        VALUES (_order_id, tc_id_from_name('contact_type', p_js ->> 'contact_type'), p_js ->> 'title', p_js ->> 'org_reg', p_js ->> 'org_vat', p_js ->> 'org_duns',(p_js ->> 'tenant_customer_id')::uuid, p_js ->> 'email', p_js ->> 'phone', p_js ->> 'phone_ext', p_js ->> 'fax', p_js ->> 'fax_ext', p_js ->> 'country', p_js ->> 'language', jsonb_array_to_text_array(p_js -> 'tags'), jsonb_array_to_text_array(p_js -> 'documentation'))
    RETURNING
        id INTO _order_contact_id;
    -- Store the order_item_create_contact
    INSERT INTO order_item_create_contact(order_id, contact_id)
        VALUES (_order_id, _order_contact_id)
    RETURNING
        id INTO _order_item_create_contact_id;
    -- store postal attributes
    FOR _postal_js IN
    SELECT
        jsonb_array_elements(p_js -> 'order_contact_postals')
        LOOP
            INSERT INTO order_contact_postal(contact_id, is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state)
                VALUES (_order_contact_id,(_postal_js ->> 'is_international')::boolean, _postal_js ->> 'first_name', _postal_js ->> 'last_name', _postal_js ->> 'org_name', _postal_js ->> 'address1', _postal_js ->> 'address2', _postal_js ->> 'address3', _postal_js ->> 'city', _postal_js ->> 'postal_code', _postal_js ->> 'state');
        END LOOP;
    -- store additional attributes
    FOR _attr_id,
    _attr_name IN
    SELECT
        a.id,
        a.name
    FROM
        attribute a
        JOIN attribute_type at ON at.id = a.type_id
            AND at.name = 'contact' LOOP
                IF NOT p_js ->> _attr_name IS NULL THEN
                    INSERT INTO order_contact_attribute(attribute_id, contact_id, value)
                        VALUES (_attr_id, _order_contact_id, p_js ->> _attr_name);
                END IF;
            END LOOP;
    RETURN _order_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION jsonb_get_create_contact_order_by_id(p_id uuid)
    RETURNS jsonb
    AS $$
DECLARE
    _order_item_create_contact_id uuid;
    _order_contact_id uuid;
BEGIN
    SELECT
        id,
        contact_id INTO STRICT _order_item_create_contact_id,
        _order_contact_id
    FROM
        order_item_create_contact
    WHERE
        order_id = p_id;
    RETURN ( -- The basic attributes of a create contact order, from the order item create contact table, plus the contact_type.name
        SELECT
            to_jsonb(oicc) AS basic_attr
        FROM (
            SELECT tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, phone_ext, fax, fax_ext, country, LANGUAGE, tags, documentation, metadata
            FROM
                order_item_create_contact cc
                JOIN order_contact oc ON oc.id = cc.contact_id
            WHERE
                cc.id = _order_item_create_contact_id) oicc) || COALESCE(( -- The additional attributes of a create contact order, from the order_contact_attribute table
                            SELECT
                                jsonb_object_agg(a.name, oca.value) AS extended_attr FROM order_contact_attribute oca
                    JOIN attribute a ON a.id = oca.attribute_id
                    WHERE
                        oca.contact_id = _order_contact_id GROUP BY oca.contact_id), '{}'::jsonb) ||( -- The contact postals of a create contact order as an object holding the array sorting the UTF-8 representation before the ASCII-only representation
                            SELECT
                                to_jsonb(ocpa)
                            FROM (
                                SELECT
                                    jsonb_agg(ocp) AS order_contact_postals
                                FROM (
                                    SELECT is_international, first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
                                    FROM order_contact_postal
                                    WHERE contact_id = _order_contact_id
                                    ORDER BY is_international ASC) ocp) ocpa) 
                                    ||
                                    (
                                        SELECT to_jsonb(o) AS order_attr
                                        FROM (
                                            SELECT id, created_date, updated_date, tenant_customer_id, customer_user_id,
                                            (
                                                SELECT to_jsonb(ot) AS type
                                                FROM (
                                                    SELECT tc_name_from_id('v_order_type', type_id) AS name) ot),
                                                    (
                                                        SELECT to_jsonb(os) AS status
                                                        FROM (
                                                            SELECT tc_name_from_id('order_status', status_id) AS name
                                                            ) os
                                                    )
                                                    FROM "order" WHERE id = p_id
                                            ) o
                                    );
                                    END;
$$ LANGUAGE plpgsql STABLE;

DROP VIEW IF EXISTS v_contact CASCADE;

CREATE VIEW v_contact AS
SELECT c.id, tc_name_from_id('contact_type', c.type_id) AS contact_type, c.tenant_customer_id, c.email, c.phone, c.phone_ext, c.fax, c.fax_ext, c.language, c.tags, c.documentation, cp.is_international, cp.first_name, cp.last_name, c.title, cp.org_name, c.org_reg, c.org_vat, c.org_duns, cp.address1, cp.address2, cp.address3, cp.city, cp.postal_code, cp.state, c.country, vca.attributes
FROM
    ONLY contact c
    JOIN ONLY contact_postal cp ON cp.contact_id = c.id
    LEFT JOIN v_contact_attribute vca ON vca.contact_id = c.id;


ALTER TABLE IF EXISTS itdp.contact
    ADD COLUMN IF NOT EXISTS phone_ext text,
    ADD COLUMN IF NOT EXISTS fax_ext text;

DO $$
DECLARE
    partition_name text;
    ext_type text := 'text';
BEGIN
    FOR partition_name IN
    SELECT
        inhrelid::regclass::text
    FROM
        pg_inherits
    WHERE
        inhparent = 'itdp.contact'::regclass LOOP
            -- Add columns
            EXECUTE format('ALTER TABLE IF EXISTS %I ADD COLUMN IF NOT EXISTS phone_ext %s', partition_name, ext_type);
            EXECUTE format('ALTER TABLE IF EXISTS %I ADD COLUMN IF NOT EXISTS fax_ext %s', partition_name, ext_type);
        END LOOP;
END
$$;

ALTER TABLE IF EXISTS itdp.contact_error_records
    ADD COLUMN IF NOT EXISTS phone_ext text,
    ADD COLUMN IF NOT EXISTS fax_ext text;

-- Migration: Add phone_ext and fax_ext data elements for each contact type
WITH 
registrant_de AS (SELECT id FROM data_element WHERE name = 'registrant'),
admin_de AS (SELECT id FROM data_element WHERE name = 'admin'),
tech_de AS (SELECT id FROM data_element WHERE name = 'tech'),
billing_de AS (SELECT id FROM data_element WHERE name = 'billing')

INSERT INTO data_element(name, descr, parent_id)
    VALUES
        -- Registrant contact
('phone_ext', 'Phone ext of the registrant',(SELECT id FROM registrant_de)),
('fax_ext', 'Fax ext of the registrant',(SELECT id FROM registrant_de)),
        -- Admin contact
('phone_ext', 'Phone ext of the admin contact',(SELECT id FROM admin_de)),
('fax_ext', 'Fax ext of the admin contact',(SELECT id FROM admin_de)),
        -- Tech contact
('phone_ext', 'Phone ext of the tech contact',(SELECT id FROM tech_de)),
('fax_ext', 'Fax ext of the tech contact',(SELECT id FROM tech_de)),
        -- Billing contact
('phone_ext', 'Phone ext of the billing contact',(SELECT id FROM billing_de)),
('fax_ext', 'Fax ext of the billing contact',(SELECT id FROM billing_de))
ON CONFLICT DO NOTHING;