-- function: provision_domain_success()
-- description: complete or continue provision order based on the status
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
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id AND pc.accreditation_id = NEW.accreditation_id
        WHERE pdc.provision_domain_id = NEW.id
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


-- function: provision_domain_failure()
-- description: fail provision order based on the status
CREATE OR REPLACE FUNCTION provision_domain_failure() RETURNS TRIGGER AS $$
BEGIN
    -- fail the provision domain update
    IF NEW.parent_id IS NOT NULL THEN
        UPDATE provision_domain_update
        SET status_id = NEW.status_id
        WHERE id = NEW.parent_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_renew_success
-- description: renews the domain in the domain table
CREATE OR REPLACE FUNCTION provision_domain_renew_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE domain
    SET expiry_date=NEW.ry_expiry_date, ry_expiry_date=NEW.ry_expiry_date
    WHERE id = NEW.domain_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_redeem_success
-- description: redeems the domain in the domain table along with contacts and hosts references
CREATE OR REPLACE FUNCTION provision_domain_redeem_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE domain_rgp_status SET
        expiry_date = NOW()
    WHERE id = (SELECT rgp_status_id FROM v_domain where id = NEW.domain_id and rgp_epp_status = 'redemptionPeriod');

    UPDATE domain SET
        deleted_date = NULL,
        ry_expiry_date = COALESCE(NEW.ry_expiry_date, ry_expiry_date)
    WHERE id = NEW.domain_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_delete_success
-- description: deletes the domain in the domain table along with contacts and hosts references
CREATE OR REPLACE FUNCTION provision_domain_delete_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE domain
    SET deleted_date = NOW()
    WHERE id = NEW.domain_id;

    IF NEW.in_redemption_grace_period THEN
        INSERT INTO domain_rgp_status(
            domain_id,
            status_id
        ) VALUES (
                     NEW.domain_id,
                     tc_id_from_name('rgp_status', 'redemption_grace_period')
                 );

    ELSE
        DELETE FROM provision_host
        WHERE domain_id = NEW.domain_id;

        -- DELETE FROM domain
        -- WHERE id = NEW.domain_id;
        PERFORM delete_domain_with_reason(NEW.domain_id, 'deleted');

        DELETE FROM provision_domain
        WHERE domain_name = NEW.domain_name;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_domain_delete_host_success
-- description: deletes domain host
CREATE OR REPLACE FUNCTION provision_domain_delete_host_success() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM ONLY host WHERE name=NEW.host_name;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


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
    ) ON CONFLICT (domain_id, domain_contact_type_id, is_private, is_privacy_proxy, is_local_presence)
        DO UPDATE SET contact_id = EXCLUDED.contact_id, handle = EXCLUDED.handle;

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


-- function: provision_domain_transfer_in_success()
-- description: complete or continue provision order based on the status
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_success() RETURNS TRIGGER AS $$
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
        ry_updated_date,
        ry_transfered_date,
        tags,
        metadata,
        uname,
        language
    ) (
        SELECT
            pdt.id,    -- domain id
            pdt.tenant_customer_id,
            pdt.accreditation_tld_id,
            pdt.domain_name,
            pdt.pw,
            pdt.roid,
            pdt.ry_created_date,
            pdt.ry_expiry_date,
            pdt.ry_expiry_date,
            pdt.updated_date,
            pdt.ry_transfered_date,
            pdt.tags,
            pdt.metadata,
            pdt.uname,
            pdt.language
        FROM provision_domain_transfer_in pdt
        WHERE id = NEW.id
    );

    -- add linked hosts
    INSERT INTO host(
        tenant_customer_id,
        domain_id,
        name
    )
    SELECT NEW.tenant_customer_id, NEW.id, * FROM UNNEST(NEW.hosts) AS name
    ON CONFLICT (tenant_customer_id,name) DO UPDATE SET domain_id = EXCLUDED.domain_id;

    -- rgp status
    INSERT INTO domain_rgp_status(
        domain_id,
        status_id
    ) VALUES (
        NEW.id,
        tc_id_from_name('rgp_status', 'transfer_grace_period')
    );

    -- secdns data
    if NEW.secdns_type = 'ds_data' then
        WITH new_secdns_ds_data AS (
            INSERT INTO secdns_ds_data(
                key_tag,
                algorithm,
                digest_type,
                digest,
                key_data_id
            )
            SELECT
                pdts.key_tag,
                pdts.algorithm,
                pdts.digest_type,
                pdts.digest,
                pdts.key_data_id
            FROM transfer_in_domain_secdns_ds_data pdts
            WHERE pdts.provision_domain_transfer_in_id = NEW.id
            RETURNING id
            ) INSERT INTO domain_secdns(
                domain_id,
                ds_data_id
            ) SELECT NEW.id, id FROM new_secdns_ds_data;

    ELSIF NEW.secdns_type = 'key_data' then
        WITH new_secdns_key_data AS (
            INSERT INTO secdns_key_data(
                flags,
                protocol,
                algorithm,
                public_key
            )
            SELECT
                pdts.flags,
                pdts.protocol,
                pdts.algorithm,
                pdts.public_key
            FROM transfer_in_domain_secdns_key_data pdts
            WHERE pdts.provision_domain_transfer_in_id = NEW.id
            RETURNING id
            ) INSERT INTO domain_secdns(
                domain_id,
                key_data_id
            ) SELECT NEW.id, id FROM new_secdns_key_data;
    end if;

    --- create domain transfer event
    PERFORM event_domain_transfer_in(NEW.id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_transfer_away_success()
-- description: delete the domain and provision domain record when the transfer away is successful
CREATE OR REPLACE FUNCTION provision_domain_transfer_away_success() RETURNS TRIGGER AS $$
BEGIN
    -- DELETE FROM domain
    -- WHERE id = NEW.domain_id;
    PERFORM delete_domain_with_reason(NEW.domain_id, 'transfered');

    DELETE FROM provision_domain
    WHERE domain_name = NEW.domain_name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_transfer_in_cancel_request_success()
-- description: completes the transfer in cancel request
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_cancel_request_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE provision_domain_transfer_in_request SET 
      transfer_status_id = tc_id_from_name('transfer_status', 'clientCancelled'), 
      status_id = tc_id_from_name('provision_status', 'completed')
    WHERE id = NEW.transfer_in_request_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
