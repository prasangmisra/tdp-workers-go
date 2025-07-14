--
-- function: registry_epp_from_json()
-- description: Parses a JSONB into the tables business_entity, registry,
-- provider, provider_protocol, provider_instance,
-- tld, provider_instance_tld,
-- provider_instance_epp, accreditation, accreditation_epp,
-- accreditation_tld, certificate_authority, tenant_cert
--
CREATE OR REPLACE FUNCTION registry_epp_from_json(registry_data JSONB) RETURNS void AS $$
BEGIN
    PERFORM seed_business_entity(registry_data);
    PERFORM seed_registry(registry_data);
    PERFORM seed_provider(registry_data);
    PERFORM seed_provider_protocol();
    PERFORM seed_provider_instance(registry_data);
    PERFORM seed_tld(registry_data);
    PERFORM seed_provider_instance_tld(registry_data);
    PERFORM seed_provider_instance_epp(registry_data);
    PERFORM seed_accreditation(registry_data);
    PERFORM seed_accreditation_epp(registry_data);
    PERFORM seed_accreditation_tld();
    PERFORM seed_certificate_authority(registry_data);
    PERFORM seed_tenant_cert(registry_data);
    PERFORM seed_accreditation_epp_cert(registry_data);
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_business_entity()
-- description: Parses a JSONB and upserts into the table business_entity
--
CREATE OR REPLACE FUNCTION seed_business_entity(registry_data JSONB) RETURNS void AS $$
BEGIN
    INSERT INTO "business_entity"(
        name,
        descr
    )
    VALUES(
        registry_data->'registry'->>'business_entity_name',
        registry_data->'registry'->>'business_entity_descr'
    )
    ON CONFLICT (name) DO 
    UPDATE SET
        descr = EXCLUDED.descr;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_registry()
-- description: Parses a JSONB and upserts into the table registry
--
CREATE OR REPLACE FUNCTION seed_registry(registry_data JSONB) RETURNS void AS $$
BEGIN
    INSERT INTO "registry"(
        business_entity_id,
        descr,
        name
    )
    VALUES(
        tc_id_from_name('business_entity', registry_data->'registry'->>'business_entity_name'),
        registry_data->'registry'->>'descr',
        registry_data->'registry'->>'name'
    )
    ON CONFLICT (name) DO 
    UPDATE SET
        descr = EXCLUDED.descr,
        business_entity_id = EXCLUDED.business_entity_id;

END;
$$ LANGUAGE plpgsql;

--
-- function: seed_provider()
-- description: Parses a JSONB and upserts into the table provider
--
CREATE OR REPLACE FUNCTION seed_provider(registry_data JSONB) RETURNS void AS $$
DECLARE
    v_provider_name text;
    v_provider_descr text;
BEGIN
    v_provider_name := registry_data->'registry'->'provider_name';
    v_provider_descr := registry_data->'registry'->'provider_descr';

    INSERT INTO "provider"(
        business_entity_id,
        name,
        descr
    )
    VALUES (
        tc_id_from_name('business_entity', registry_data->'registry'->>'business_entity_name'),
        trim('"' FROM v_provider_name),
        trim('"' FROM v_provider_descr)
    )
    ON CONFLICT (name) DO 
    UPDATE SET
        business_entity_id = EXCLUDED.business_entity_id,
        descr = EXCLUDED.descr;

END;
$$ LANGUAGE plpgsql;

--
-- function: seed_provider_protocol()
-- description: Inserts into provider_protocol with new provider rows.
--
CREATE OR REPLACE FUNCTION seed_provider_protocol() RETURNS void AS $$
BEGIN
    INSERT INTO provider_protocol(provider_id,supported_protocol_id)
    (SELECT bp.id,p.id FROM provider bp,supported_protocol p )
    ON CONFLICT (provider_id, supported_protocol_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_provider_instance()
-- description: Parses a JSONB and upserts into the table provider_instance
--
CREATE OR REPLACE FUNCTION seed_provider_instance(registry_data JSONB) RETURNS void AS $$
BEGIN
    INSERT INTO "provider_instance"(
        provider_id,
        name,
        descr,
        is_proxy
    )
    VALUES(
        tc_id_from_name('provider', registry_data->'registry'->>'provider_name'),
        registry_data->'registry'->'provider_instance'->>'name',
        registry_data->'registry'->'provider_instance'->>'descr',
        (registry_data->'registry'->'provider_instance'->>'is_proxy')::BOOLEAN
    )
    ON CONFLICT (name) DO 
    UPDATE SET 
        provider_id = EXCLUDED.provider_id,
        descr = EXCLUDED.descr,
        is_proxy = EXCLUDED.is_proxy;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_tld()
-- description: Iterates over the tlds in the JSONB and inserts them into the tld table.
--
CREATE OR REPLACE FUNCTION seed_tld(registry_data JSONB) RETURNS void AS $$
DECLARE
    v_tld_name text;
    v_tld text;
    v_registry_name text;
    v_old_registry text;
BEGIN
    FOR v_tld IN SELECT * FROM jsonb_array_elements(registry_data->'registry'->'tlds')
    LOOP
        v_tld_name := trim('"' FROM v_tld);

        -- Check to see if the TLD already exists, returning the registry it belongs to.
        v_registry_name := registry_data->'registry'->>'name';

        SELECT r.name INTO v_old_registry 
        FROM tld t
        JOIN registry r ON t.registry_id = r.id
        WHERE t.name = v_tld_name AND r.name <> v_registry_name;

        IF FOUND THEN
            RAISE EXCEPTION 'TLD name "%" conflict with new registry: "%", old registry: "%"', v_tld_name, v_registry_name, v_old_registry;
        END IF;

        INSERT INTO "tld"(
            name,
            registry_id
        )
        VALUES(
            v_tld_name,
            tc_id_from_name('registry', v_registry_name)
        )
        ON CONFLICT (name) DO NOTHING;

    END LOOP;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_provider_instance_tld()
-- description: Parses a JSONB and upserts into the table provider_instance_tld
--
CREATE OR REPLACE FUNCTION seed_provider_instance_tld(registry_data JSONB) RETURNS void AS $$
DECLARE
    v_tld text;
    v_tld_id UUID;
    v_provider_instance_id UUID;
BEGIN
    v_provider_instance_id := tc_id_from_name('provider_instance', registry_data->'registry'->'provider_instance'->>'name');

    FOR v_tld IN SELECT * FROM jsonb_array_elements(registry_data->'registry'->'tlds')
    LOOP
        v_tld_id := tc_id_from_name('tld', trim('"' FROM v_tld));

        IF v_tld_id IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM provider_instance_tld p WHERE p.tld_id = v_tld_id) THEN
                    UPDATE provider_instance_tld
                    SET provider_instance_id = v_provider_instance_id
                    WHERE tld_id = v_tld_id;
            ELSE
                INSERT INTO "provider_instance_tld"(
                    tld_id,
                    provider_instance_id
                )
                VALUES(
                    v_tld_id,
                    v_provider_instance_id
                );
            END IF;
        END IF;

        -- Reset v_tld_id for the next v_tld
        v_tld_id := NULL;

    END LOOP;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_provider_instance_epp()
-- description: Parses a JSONB and upserts into the table provider_instance_epp
--
CREATE OR REPLACE FUNCTION seed_provider_instance_epp(registry_data JSONB) RETURNS void AS $$
BEGIN

    INSERT INTO "provider_instance_epp"(
        provider_instance_id,
        host,
        port,
        conn_min,
        conn_max,
        ssl_verify_host,
        ssl_verify,
        xml_verify_schema,
        keepalive_seconds,
        session_max_cmd,
        session_max_sec
    )
    VALUES(
        tc_id_from_name('provider_instance', registry_data->'registry'->'provider_instance'->>'name'),
        registry_data->'registry'->'provider_instance'->>'host',
        (registry_data->'registry'->'provider_instance'->>'port')::integer,
        (registry_data->'registry'->'accreditation'->>'conn_min')::integer,
        (registry_data->'registry'->'accreditation'->>'conn_max')::integer,
        (registry_data->'registry'->'accreditation'->>'ssl_verify_host')::boolean,
        (registry_data->'registry'->'accreditation'->>'ssl_verify')::boolean,
        (registry_data->'registry'->'accreditation'->>'xml_verify_schema')::boolean,
        (registry_data->'registry'->'accreditation'->>'keepalive_seconds')::integer,
        (registry_data->'registry'->'accreditation'->>'session_max_cmd')::integer,
        (registry_data->'registry'->'accreditation'->>'session_max_sec')::integer
    )
    ON CONFLICT (provider_instance_id) DO 
    UPDATE SET
        host = EXCLUDED.host,
        port = EXCLUDED.port,
        conn_min = EXCLUDED.conn_min,
        conn_max = EXCLUDED.conn_max,
        ssl_verify_host = EXCLUDED.ssl_verify,
        ssl_verify = EXCLUDED.ssl_verify,
        xml_verify_schema = EXCLUDED.xml_verify_schema,
        keepalive_seconds = EXCLUDED.keepalive_seconds,
        session_max_cmd = EXCLUDED.session_max_cmd,
        session_max_sec = EXCLUDED.session_max_sec;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_accreditation()
-- description: Parses a JSONB into the table accreditation
--
CREATE OR REPLACE FUNCTION seed_accreditation(registry_data JSONB) RETURNS void AS $$
BEGIN
    INSERT INTO "accreditation"(
        provider_instance_id,
        name,
        tenant_id,
        registrar_id
    )
    VALUES(
        tc_id_from_name('provider_instance', registry_data->'registry'->'provider_instance'->>'name'),
        registry_data->'registry'->'accreditation'->>'name',
        tc_id_from_name('tenant',registry_data->'registry'->'accreditation'->>'tenant_name'),
        registry_data->'registry'->'accreditation'->>'registrar_id'
    )
    ON CONFLICT (name) DO 
    UPDATE SET
        provider_instance_id = EXCLUDED.provider_instance_id,
        tenant_id = EXCLUDED.tenant_id,
        registrar_id = EXCLUDED.registrar_id;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_accreditation_epp()
-- description: Parses a JSONB and upserts into the table accreditation_epp
--
CREATE OR REPLACE FUNCTION seed_accreditation_epp(registry_data JSONB) RETURNS void AS $$
DECLARE
    v_accreditation_id UUID;
BEGIN
    v_accreditation_id := tc_id_from_name('accreditation', registry_data->'registry'->'accreditation'->>'name');

    IF v_accreditation_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM accreditation_epp WHERE accreditation_id = v_accreditation_id) THEN
            INSERT INTO "accreditation_epp"(
                accreditation_id,
                clid,
                pw,
                port,
                conn_min,
                conn_max,
                ssl_verify_host,
                ssl_verify,
                xml_verify_schema,
                keepalive_seconds,
                session_max_cmd,
                session_max_sec
            )
            VALUES(
                v_accreditation_id,
                registry_data->'registry'->'accreditation'->>'clid',
                registry_data->'registry'->'accreditation'->>'pw',
                (registry_data->'registry'->'provider_instance'->>'port')::integer,
                (registry_data->'registry'->'accreditation'->>'conn_min')::integer,
                (registry_data->'registry'->'accreditation'->>'conn_max')::integer,
                (registry_data->'registry'->'accreditation'->>'ssl_verify_host')::boolean,
                (registry_data->'registry'->'accreditation'->>'ssl_verify')::boolean,
                (registry_data->'registry'->'accreditation'->>'xml_verify_schema')::boolean,
                (registry_data->'registry'->'accreditation'->>'keepalive_seconds')::integer,
                (registry_data->'registry'->'accreditation'->>'session_max_cmd')::integer,
                (registry_data->'registry'->'accreditation'->>'session_max_sec')::integer
            );
        ELSE
            UPDATE accreditation_epp
            SET 
                clid = registry_data->'registry'->'accreditation'->>'clid',
                pw = registry_data->'registry'->'accreditation'->>'pw',
                port = (registry_data->'registry'->'provider_instance'->>'port')::integer,
                conn_min = (registry_data->'registry'->'accreditation'->>'conn_min')::integer,
                conn_max = (registry_data->'registry'->'accreditation'->>'conn_max')::integer,
                ssl_verify_host = (registry_data->'registry'->'accreditation'->>'ssl_verify_host')::boolean,
                ssl_verify = (registry_data->'registry'->'accreditation'->>'ssl_verify')::boolean,
                xml_verify_schema = (registry_data->'registry'->'accreditation'->>'xml_verify_schema')::boolean,
                session_max_cmd = (registry_data->'registry'->'accreditation'->>'session_max_cmd')::integer,
                session_max_sec = (registry_data->'registry'->'accreditation'->>'session_max_sec')::integer,
                keepalive_seconds = (registry_data->'registry'->'accreditation'->>'keepalive_seconds')::integer
            WHERE accreditation_id = v_accreditation_id;
        END IF;
    END IF;

END;
$$ LANGUAGE plpgsql;

--
-- function: seed_accreditation_tld()
-- description: Inserts into accreditation_tld new rows based on provider_instance_tld and accreditation
--
CREATE OR REPLACE FUNCTION seed_accreditation_tld() RETURNS void AS $$
BEGIN
    INSERT INTO accreditation_tld(accreditation_id,provider_instance_tld_id)
        (SELECT a.id, p.id
        FROM provider_instance_tld p
        JOIN accreditation a ON a.provider_instance_id=p.provider_instance_id)
    ON CONFLICT (accreditation_id,provider_instance_tld_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_certificate_authority()
-- description: Parses a JSONB and upserts into the table certificate_authority
--
CREATE OR REPLACE FUNCTION seed_certificate_authority(registry_data JSONB) RETURNS void AS $$
BEGIN
    -- cacert might be provided even if cert/key are not
    IF registry_data->'registry'->>'key' <> '' OR registry_data->'registry'->>'cacert' <> '' THEN
        INSERT INTO certificate_authority(
            name,
            descr,
            cert
        )
        VALUES(
            registry_data->'registry'->>'cacert_name',
            registry_data->'registry'->>'cacert_descr',
            registry_data->'registry'->>'cacert'
        )
        ON CONFLICT (name) DO 
        UPDATE SET 
            descr = EXCLUDED.descr,
            cert = EXCLUDED.cert;
    END IF;
END;
$$ LANGUAGE plpgsql;

--
-- function: seed_tenant_cert()
-- description: Parses a JSONB and upserts into the table tenant_cert
--
CREATE OR REPLACE FUNCTION seed_tenant_cert(registry_data JSONB) RETURNS void AS $$
DECLARE
    v_cert_name text;
BEGIN
    v_cert_name := registry_data->'registry'->>'cert_name';

    IF registry_data->'registry'->>'key' <> '' OR registry_data->'registry'->>'cacert' <> '' THEN
        IF NOT EXISTS (SELECT 1 FROM tenant_cert WHERE name = v_cert_name) THEN
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
                tc_id_from_name('certificate_authority', registry_data->'registry'->>'cacert_name')
            );
        ELSE
            UPDATE tenant_cert
            SET
                cert = registry_data->'registry'->>'cert',
                key = registry_data->'registry'->>'key',
                ca_id = tc_id_from_name('certificate_authority', registry_data->'registry'->>'cacert_name')
            WHERE name = v_cert_name;
        END IF;
    END IF;

END;
$$ LANGUAGE plpgsql;

--
-- function: seed_accreditation_epp_cert()
-- description: Updates accreditation from registry_data with new cert_id
--
CREATE OR REPLACE FUNCTION seed_accreditation_epp_cert(registry_data JSONB) RETURNS void AS $$
BEGIN

    IF registry_data->'registry'->>'key' <> '' OR registry_data->'registry'->>'cacert' <> '' THEN
        UPDATE accreditation_epp
        SET
            cert_id = tc_id_from_name('tenant_cert', registry_data->'registry'->>'cert_name')
        WHERE accreditation_id = tc_id_from_name('accreditation', registry_data->'registry'->'accreditation'->>'name');
    END IF;
END;
$$ LANGUAGE plpgsql;