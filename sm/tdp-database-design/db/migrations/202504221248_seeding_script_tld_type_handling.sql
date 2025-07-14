CREATE OR REPLACE FUNCTION seed_provider(registry_data JSONB) RETURNS void AS $$
DECLARE
    v_provider_name text;
    v_provider_descr text;
BEGIN
    v_provider_name := registry_data->'registry'->>'provider_name';
    v_provider_descr := registry_data->'registry'->>'provider_descr';

    INSERT INTO "provider"(
        business_entity_id,
        name,
        descr
    )
    VALUES (
               tc_id_from_name('business_entity', registry_data->'registry'->>'business_entity_name'),
               v_provider_name,
               v_provider_descr
           )
    ON CONFLICT (name) DO
        UPDATE SET
                   business_entity_id = EXCLUDED.business_entity_id,
                   descr = EXCLUDED.descr;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION seed_tld(registry_data JSONB) RETURNS void AS $$
DECLARE
    v_tld_name text;
    v_tld RECORD;
    v_registry_name text;
    v_old_registry text;
    v_type_id UUID;
BEGIN
    FOR v_tld IN (
        SELECT 'country_code' AS type, value AS name
        FROM jsonb_array_elements_text(registry_data->'registry'->'tlds'->'cctld')
        UNION ALL
        SELECT 'generic' AS type, value AS name
        FROM jsonb_array_elements_text(registry_data->'registry'->'tlds'->'gtld')
    )
        LOOP
            v_tld_name := v_tld.name;
            v_type_id := tc_id_from_name('tld_type', v_tld.type);
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
                registry_id,
                type_id
            )
            VALUES(
                      v_tld_name,
                      tc_id_from_name('registry', v_registry_name),
                      v_type_id
                  )
            ON CONFLICT (name) DO NOTHING;

        END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION seed_provider_instance_tld(registry_data JSONB) RETURNS void AS $$
DECLARE
    v_tld text;
    v_tld_id UUID;
    v_provider_instance_id UUID;
BEGIN
    v_provider_instance_id := tc_id_from_name('provider_instance', registry_data->'registry'->'provider_instance'->>'name');

    FOR v_tld IN (
        SELECT jsonb_array_elements_text(registry_data->'registry'->'tlds'->'cctld')
        UNION ALL
        SELECT jsonb_array_elements_text(registry_data->'registry'->'tlds'->'gtld')
    )
        LOOP
            v_tld_id := tc_id_from_name('tld', v_tld);

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


CREATE OR REPLACE FUNCTION seed_accreditation_tld(registry_data JSONB) RETURNS void AS $$
DECLARE
    tld_array TEXT[];
BEGIN
    -- Extract the TLDs array from the registry_data JSON
    SELECT array_agg(tld) INTO tld_array
    FROM (
             SELECT jsonb_array_elements_text(registry_data->'registry'->'tlds'->'cctld') AS tld
             UNION ALL
             SELECT jsonb_array_elements_text(registry_data->'registry'->'tlds'->'gtld') AS tld
         ) subquery;

    -- Insert accreditation_tld records only for TLDs that are in the provided JSON data
    INSERT INTO accreditation_tld(accreditation_id, provider_instance_tld_id)
        (
            SELECT a.id, p.id
            FROM provider_instance_tld p
                     JOIN accreditation a ON a.provider_instance_id = p.provider_instance_id
                     JOIN tld t ON p.tld_id = t.id
            WHERE t.name = ANY(tld_array)
        )
    ON CONFLICT (accreditation_id, provider_instance_tld_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
