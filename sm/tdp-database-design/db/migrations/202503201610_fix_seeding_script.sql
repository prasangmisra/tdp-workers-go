DROP FUNCTION IF EXISTS seed_accreditation_tld;
CREATE OR REPLACE FUNCTION seed_accreditation_tld(registry_data JSONB) RETURNS void AS $$
DECLARE
    tld_array TEXT[];
BEGIN
    -- Extract the TLDs array from the registry_data JSON
    SELECT array_agg(tld) INTO tld_array
    FROM jsonb_array_elements_text(registry_data->'registry'->'tlds') AS tld;

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


DROP FUNCTION IF EXISTS registry_epp_from_json;
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
    PERFORM seed_accreditation_tld(registry_data);
    PERFORM seed_certificate_authority(registry_data);
    PERFORM seed_tenant_cert(registry_data);
    PERFORM seed_accreditation_epp_cert(registry_data);
END;
$$ LANGUAGE plpgsql;

