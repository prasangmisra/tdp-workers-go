--Changed the unique constraint on domain_contact table to include is_privacy_proxy and is_local_presence columns
--
ALTER TABLE public.domain_contact DROP CONSTRAINT IF EXISTS  domain_contact_domain_id_domain_contact_type_id_key;
ALTER TABLE public.domain_contact DROP CONSTRAINT IF EXISTS  domain_contact_domain_id_type_id_is_private_privacy_local_key;

ALTER TABLE public.domain_contact ADD CONSTRAINT  domain_contact_domain_id_type_id_is_private_privacy_local_key
UNIQUE (domain_id, domain_contact_type_id, is_private,is_privacy_proxy,is_local_presence);

--Changes in ITDP schema
DO $$ BEGIN   
	 IF to_regtype('itdp.dm_result_add') IS NULL THEN
        CREATE TYPE itdp.dm_result_add AS (status varchar(20), date timestamptz, result itdp.dm_result );
    END IF;
END $$;

ALTER  TABLE  itdp.tld DROP IF EXISTS min_nameservers,
 					   ADD IF NOT EXISTS   Private_Contact itdp.dm_result_add, 					  
 					   ADD IF NOT EXISTS   Contact_Attribute itdp.dm_result_add;

ALTER TABLE itdp.contact ADD IF NOT EXISTS is_private boolean default FALSE;
ALTER TABLE itdp.contact_error_records  ADD IF NOT EXISTS is_private boolean default FALSE;
ALTER TABLE dm_enom.contact ADD IF NOT EXISTS is_private boolean default FALSE;
                      

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
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id AND pc.accreditation_id = NEW.accreditation_id
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id, is_private, is_privacy_proxy, is_local_presence) DO NOTHING;

    DELETE FROM domain_contact dc
    USING provision_domain_update_rem_contact pduc
    WHERE dc.domain_id = NEW.domain_id
      AND dc.contact_id = pduc.contact_id
      AND dc.domain_contact_type_id = pduc.contact_type_id
      AND pduc.provision_domain_update_id = NEW.id;

    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            NEW.domain_id,
            pdac.contact_id,
            pdac.contact_type_id,
            pc.handle
        FROM provision_domain_update_add_contact pdac
                 JOIN provision_contact pc ON pc.contact_id = pdac.contact_id AND pc.accreditation_id = NEW.accreditation_id
        WHERE pdac.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id, is_private, is_privacy_proxy, is_local_presence)
        DO UPDATE SET contact_id = EXCLUDED.contact_id, handle = EXCLUDED.handle;



    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            NEW.domain_id,
            h.id
        FROM provision_domain_update_add_host pduah
            JOIN ONLY host h ON h.id = pduah.host_id
        WHERE pduah.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete association for removed hosts
    WITH removed_hosts AS (
        SELECT h.*
        FROM provision_domain_update_rem_host pdurh
            JOIN ONLY host h ON h.id = pdurh.host_id
        WHERE pdurh.provision_domain_update_id = NEW.id
    )
    DELETE FROM
        domain_host dh
    WHERE dh.domain_id = NEW.domain_id
        AND dh.host_id IN (SELECT id FROM removed_hosts);

    -- update auto renew flag if changed
    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew),
        auth_info = COALESCE(NEW.auth_info, d.auth_info),
        secdns_max_sig_life = COALESCE(NEW.secdns_max_sig_life, d.secdns_max_sig_life)
    WHERE d.id = NEW.domain_id;

    -- update locks
    IF NEW.locks IS NOT NULL THEN
        PERFORM update_domain_locks(NEW.domain_id, NEW.locks);
    end if;

    -- handle secdns to be removed
    PERFORM remove_domain_secdns_data(
        NEW.domain_id,
        ARRAY(
            SELECT udrs.id
            FROM provision_domain_update_rem_secdns pdurs
            JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            WHERE pdurs.provision_domain_update_id = NEW.id
        )
    );

    -- handle secdns to be added
    PERFORM add_domain_secdns_data(
        NEW.domain_id,
        ARRAY(
            SELECT udas.id
            FROM provision_domain_update_add_secdns pduas
            JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
            WHERE pduas.provision_domain_update_id = NEW.id
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
