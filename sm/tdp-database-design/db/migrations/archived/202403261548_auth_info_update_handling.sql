--
-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
BEGIN

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            NEW.domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_update_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
        DO UPDATE SET contact_id = EXCLUDED.contact_id;

    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            NEW.domain_id,
            h.id
        FROM ONLY host h
        WHERE h.name IN (SELECT UNNEST(NEW.hosts))
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete removed hosts
    DELETE FROM
        domain_host dh
        USING
            host h
    WHERE
        NEW.hosts IS NOT NULL
      AND h.name NOT IN (SELECT UNNEST(NEW.hosts))
      AND dh.domain_id = NEW.domain_id
      AND dh.host_id = h.id;

    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew),
        auth_info = COALESCE(NEW.auth_info, d.auth_info)
    WHERE d.id = NEW.domain_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;