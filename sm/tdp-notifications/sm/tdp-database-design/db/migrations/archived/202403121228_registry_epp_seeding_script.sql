-- fixed rerunning the script for already existing accreditation
-- special cases for seeding ca cert when no cert/key are provided

CREATE OR REPLACE FUNCTION registry_epp_from_json(registry_data JSONB) RETURNS void AS $$
DECLARE
    business_entity_id UUID;
    registry_id UUID;
    tld text;
    prov_id UUID;
    provider_instance_is_proxy BOOLEAN;
    prov_instance_id UUID;
    accred_id UUID;
    tld_id UUID;
    crt_id UUID;
    ca_id UUID;
    provider_name text;
    provider_descr text;
BEGIN
    
    --Seed into business_entity
    INSERT INTO "business_entity"(
        name,
        descr
    )
    VALUES(
        registry_data->'registry'->>'business_entity_name',
        registry_data->'registry'->>'business_entity_descr'
    )
    ON CONFLICT (name) DO NOTHING
    RETURNING id INTO business_entity_id;

    IF business_entity_id IS NULL THEN
        business_entity_id := tc_id_from_name('business_entity', registry_data->'registry'->>'business_entity_name');
    END IF;

    --Seed into registry
    INSERT INTO "registry"(
        business_entity_id,
        descr,
        name
    )
    VALUES(
        business_entity_id,
        registry_data->'registry'->>'descr',
        registry_data->'registry'->>'name'
    )
    ON CONFLICT (name) DO NOTHING
    RETURNING id INTO registry_id;

    IF registry_id IS NULL THEN
        registry_id := tc_id_from_name('registry', registry_data->'registry'->>'name');
    END IF;

    --Seed into provider 
    provider_name := registry_data->'registry'->'provider_name';
    provider_descr := registry_data->'registry'->'provider_descr';

    INSERT INTO "provider"(
        business_entity_id,
        name,
        descr
    )
    VALUES(
        business_entity_id,
        trim('"' FROM provider_name),
        trim('"' FROM provider_descr)
    )
    ON CONFLICT (name) DO NOTHING
    RETURNING id INTO prov_id;

    IF prov_id IS NULL THEN
        prov_id := tc_id_from_name('provider', trim('"' FROM provider_name));
    END IF;

    --Seed into provider_protocol
    INSERT INTO provider_protocol(provider_id,supported_protocol_id)
    (SELECT bp.id,p.id FROM provider bp,supported_protocol p )
    ON CONFLICT (provider_id, supported_protocol_id) DO NOTHING;

    --Seed into provider_instance
    provider_instance_is_proxy := registry_data->'registry'->'provider_instance'->>'is_proxy';

    INSERT INTO "provider_instance"(
        provider_id,
        name,
        descr,
        is_proxy
    )
    VALUES(
        prov_id,
        registry_data->'registry'->'provider_instance'->>'name',
        registry_data->'registry'->'provider_instance'->>'descr',
        provider_instance_is_proxy
    )
    ON CONFLICT (name) DO NOTHING
    RETURNING id INTO prov_instance_id;

    IF prov_instance_id IS NULL THEN
        prov_instance_id := tc_id_from_name('provider_instance', registry_data->'registry'->'provider_instance'->>'name');
    END IF;

    --Seed into tld and provider_instance_tld
    FOR tld IN SELECT * FROM jsonb_array_elements(registry_data->'registry'->'tlds')
    LOOP
        INSERT INTO "tld"(
            name,
            registry_id
        )
        VALUES(
            trim('"' FROM tld),
            registry_id
        )
        ON CONFLICT (name) DO NOTHING
        RETURNING id INTO tld_id;

        IF tld_id IS NOT NULL THEN
            INSERT INTO "provider_instance_tld"(
                tld_id,
                provider_instance_id
            )
            VALUES(
                tld_id,
                prov_instance_id
            );
        END IF;
        tld_id := NULL;
    END LOOP;

    --Seed into provider_instance_epp
    --Provides a default port value of 700 JSON value is null ie. not provided
    INSERT INTO "provider_instance_epp"(
        provider_instance_id,
        host,
        port
    )
    VALUES(
        prov_instance_id,
        registry_data->'registry'->'provider_instance'->>'host',
        COALESCE(registry_data->'registry'->'provider_instance'->>'port', '700')::integer
    )
    ON CONFLICT (provider_instance_id) DO NOTHING;

    --Seed into accreditation
    INSERT INTO "accreditation"(
        provider_instance_id,
        name,
        tenant_id
    )
    VALUES(
        prov_instance_id,
        registry_data->'registry'->'accreditation'->>'name',
        tc_id_from_name('tenant',registry_data->'registry'->'accreditation'->>'tenant_name')
    )
    ON CONFLICT (name) DO NOTHING
    RETURNING id INTO accred_id;

    IF accred_id IS NULL THEN
        accred_id := tc_id_from_name('accreditation', registry_data->'registry'->'accreditation'->>'name');
    ELSE
        -- Seed into accreditation_epp only when accreditation was actually inserted
        INSERT INTO "accreditation_epp"(
            accreditation_id,
            clid,
            pw,
            port
        )
        VALUES(
            accred_id,
            registry_data->'registry'->'accreditation'->>'clid',
            registry_data->'registry'->'accreditation'->>'pw',
            COALESCE(registry_data->'registry'->'accreditation'->>'port', '700')::integer
        );
    END IF;

    --Seed into accreditation_tld
    INSERT INTO accreditation_tld(accreditation_id,provider_instance_tld_id)
    (SELECT a.id, p.id
        FROM provider_instance_tld p
            JOIN accreditation a ON a.provider_instance_id=p.provider_instance_id)
            ON CONFLICT (accreditation_id,provider_instance_tld_id) DO NOTHING;

    -- cacert might be provided even if cert/key are not
    IF registry_data->'registry'->>'key' <> '' OR registry_data->'registry'->>'cacert' <> '' THEN
        -- Seed into certificate_authority
        -- if ca cert already exists just return id
        INSERT INTO certificate_authority(
            name,
            descr,
            cert
        )
        VALUES(
            registry_data->'registry'->>'cacert_name',
            registry_data->'registry'->>'cacert_desc',
            registry_data->'registry'->>'cacert'
        )
        ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name RETURNING id INTO ca_id;

        INSERT INTO "tenant_cert"(
            name,
            cert,
            key,
            ca_id
        )
        VALUES(
            registry_data->'registry'->>'cert_name',
            registry_data->'registry'->>'cert',
            registry_data->'registry'->>'key',
            ca_id
        )
        RETURNING id INTO crt_id;

        --Updates existing accreditation_epp row to new cert id
        UPDATE accreditation_epp
        SET
            cert_id = crt_id
        WHERE accreditation_id = accred_id;

    END IF;

END;
$$ LANGUAGE plpgsql;
