CREATE OR REPLACE FUNCTION provision_domain_success() RETURNS TRIGGER AS $$
DECLARE
    v_domain_secdns_id UUID;
BEGIN
    -- domain
    INSERT INTO domain(
        id,
        tenant_customer_id,
        accreditation_tld_id,
        name,
        auth_info,
        roid,
        ry_created_date,
        ry_expiry_date,
        expiry_date,
        auto_renew,
        secdns_max_sig_life,
        uname,
        language,
        tags,
        metadata
    ) (
        SELECT
            pd.id,    -- domain id
            pd.tenant_customer_id,
            pd.accreditation_tld_id,
            pd.domain_name,
            pd.pw,
            pd.roid,
            COALESCE(pd.ry_created_date,pd.created_date),
            COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
            COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
            pd.auto_renew,
            pd.secdns_max_sig_life,
            COALESCE(pd.uname,pd.domain_name),
            pd.language,
            pd.tags,
            pd.metadata
        FROM provision_domain pd
        WHERE id = NEW.id
    );

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            pdc.provision_domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_id = NEW.id AND pc.accreditation_id = NEW.accreditation_id
    );

    -- host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            provision_domain_id,
            host_id
        FROM provision_domain_host
        WHERE provision_domain_id = NEW.id
    );

    -- rgp status
    INSERT INTO domain_rgp_status(
        domain_id,
        status_id
    ) VALUES (
        NEW.id,
        tc_id_from_name('rgp_status', 'add_grace_period')
    );

    -- secdns data
    WITH key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_secdns pds 
                JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                JOIN order_secdns_key_data oskd ON oskd.id = cds.key_data_id
            WHERE pds.provision_domain_id = NEW.id
        ) RETURNING id
    ), ds_key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_secdns pds 
                JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = cds.ds_data_id
                JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            WHERE pds.provision_domain_id = NEW.id
        ) RETURNING id
    ), ds_data AS (
        INSERT INTO secdns_ds_data
        (
            SELECT 
                osdd.id,
                osdd.key_tag,
                osdd.algorithm,
                osdd.digest_type,
                osdd.digest,
                dkd.id AS key_data_id
            FROM provision_domain_secdns pds 
                JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = cds.ds_data_id
                LEFT JOIN ds_key_data dkd ON dkd.id = osdd.key_data_Id
            WHERE pds.provision_domain_id = NEW.id
        ) RETURNING id
    )
    INSERT INTO domain_secdns (
        domain_id,
        ds_data_id,
        key_data_id
    )(
        SELECT NEW.id, NULL, id FROM key_data
        
        UNION ALL
        
        SELECT NEW.id, id, NULL FROM ds_data
    );

    -- start the provision domain update
    IF NEW.parent_id IS NOT NULL THEN
        UPDATE provision_domain_update
        SET is_complete = TRUE, domain_id = NEW.id
        WHERE id = NEW.parent_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
