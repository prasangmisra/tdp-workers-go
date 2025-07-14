CREATE OR REPLACE VIEW v_host AS
SELECT 
    h.id,
    h.tenant_customer_id,
    h.name,
    h.domain_id AS parent_domain_id,
    d.name AS parent_domain_name,
    h.tags,
    h.metadata,
    addr.addresses
FROM ONLY host h
LEFT JOIN 
    domain d ON h.domain_id = d.id
LEFT JOIN LATERAL (
    SELECT ARRAY_AGG(address) AS addresses
    FROM ONLY host_addr
    WHERE host_id = h.id
) addr ON TRUE;

-- include short_id in jsonb_get_contact_by_id
CREATE OR REPLACE FUNCTION jsonb_get_contact_by_id(p_id UUID) RETURNS JSONB AS $$
BEGIN
    RETURN
        ( -- The basic attributes of a contact, from the contact table, plus the contact_type.name
            SELECT to_jsonb(c) AS basic_attr
            FROM (
                SELECT id, short_id, tc_name_from_id('contact_type', type_id) AS contact_type, title, org_reg, org_vat, org_duns, tenant_customer_id, email, phone, fax, country, language, tags, documentation, metadata
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
-- get_domain_info is used to get domain info
-- description: get domain info with contacts and hosts data
--
CREATE OR REPLACE FUNCTION get_domain_info(
    p_name                      TEXT,
    p_include_contacts_data     BOOLEAN DEFAULT FALSE,
    p_include_hosts_data        BOOLEAN DEFAULT FALSE,
    p_include_nameservers_data  BOOLEAN DEFAULT FALSE,
    p_include_secdns_data       BOOLEAN DEFAULT FALSE
) RETURNS JSONB AS $$
DECLARE
    _domain_info JSONB;
BEGIN
    -- v_domain data
    SELECT row_to_json(vd.*) INTO _domain_info
    FROM v_domain vd
    WHERE name = p_name OR uname = p_name;

    IF _domain_info IS NULL THEN
        RAISE EXCEPTION 'Domain not found' USING ERRCODE = 'no_data_found';
    END IF;

    -- include contacts data else include contact id + type
    IF p_include_contacts_data THEN
        _domain_info = _domain_info || jsonb_build_object('contacts',
            (SELECT jsonb_agg(jsonb_get_contact_by_id(dc.contact_id) || jsonb_build_object('type', dct.name))
            FROM domain_contact dc
            JOIN domain_contact_type dct ON dct.id = dc.domain_contact_type_id
            WHERE dc.domain_id = (_domain_info->>'id')::UUID)
       );
    ELSE
        _domain_info = _domain_info || jsonb_build_object('contacts',
            (SELECT jsonb_agg(jsonb_build_object('id', c.id, 'short_id', c.short_id, 'type', dct.name))
            FROM contact c
            JOIN domain_contact dc ON c.id = dc.contact_id
            JOIN domain_contact_type dct ON dct.id = dc.domain_contact_type_id
            WHERE dc.domain_id = (_domain_info->>'id')::UUID)
        );
    END IF;

    -- include nameservers data
    IF p_include_nameservers_data THEN
        _domain_info = _domain_info || jsonb_build_object('nameservers',
            (SELECT jsonb_agg(jsonb_build_object(
                'id', h.id,
                'name', h.name,
                'addresses', h.addresses,
                'tags', h.tags,
                'metadata', h.metadata
                )
            )
            FROM domain_host dh
            JOIN v_host h ON h.id = dh.host_id
            WHERE dh.domain_id = (_domain_info->>'id')::UUID)
        );
    END IF;


    -- include hosts data
    IF p_include_hosts_data THEN
        _domain_info = _domain_info || jsonb_build_object('hosts',
            (SELECT jsonb_agg(jsonb_build_object(
                'id', h.id,
                'name', h.name,
                'addresses', h.addresses,
                'tags', h.tags,
                'metadata', h.metadata
                )
            )
            FROM v_host h
            WHERE h.parent_domain_id = (_domain_info->>'id')::UUID)
        );
    END IF;

    -- include secdns data
    IF p_include_secdns_data THEN
        _domain_info = _domain_info || jsonb_build_object('secdns',
            (SELECT jsonb_agg(jsonb_build_object(
                'key_data', (
                    SELECT json_agg(jsonb_build_object(
                        'flags', skd.flags,
                        'protocol', skd.protocol,
                        'algorithm', skd.algorithm,
                        'public_key', skd.public_key
                    ))
                    FROM ONLY domain_secdns ds
                    LEFT JOIN ONLY secdns_key_data skd ON skd.id = ds.key_data_id
                    WHERE ds.domain_id = (_domain_info->>'id')::UUID AND ds.key_data_id IS NOT NULL
                ),
                'ds_data', (
                    SELECT json_agg(jsonb_build_object(
                        'key_tag', sdd.key_tag,
                        'algorithm', sdd.algorithm,
                        'digest_type', sdd.digest_type,
                        'digest', sdd.digest,
                        'key_data',
                        CASE
                            WHEN sdd.key_data_id IS NOT NULL THEN
                                jsonb_build_object(
                                    'flags', skd.flags,
                                    'protocol', skd.protocol,
                                    'algorithm', skd.algorithm,
                                    'public_key', skd.public_key
                                )
                        END
                    ))
                    FROM ONLY domain_secdns ds
                    JOIN ONLY secdns_ds_data sdd ON sdd.id = ds.ds_data_id
                    LEFT JOIN ONLY secdns_key_data skd ON skd.id = sdd.key_data_id
                    WHERE ds.domain_id = (_domain_info->>'id')::UUID AND ds.ds_data_id IS NOT NULL
                )
            ))
            FROM domain_secdns ds
            WHERE ds.domain_id = (_domain_info->>'id')::UUID)
        );
    END IF;

    RETURN _domain_info;
END;
$$ LANGUAGE plpgsql;
