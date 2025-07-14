-- Drop the exclusion constraint on the accreditation table
ALTER TABLE IF EXISTS accreditation DROP CONSTRAINT IF EXISTS accreditation_tenant_id_provider_instance_id_service_range_excl;
