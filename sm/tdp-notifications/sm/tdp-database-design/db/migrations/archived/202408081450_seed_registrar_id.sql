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