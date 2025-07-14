ALTER TABLE provision_domain_transfer_in
    ADD COLUMN IF NOT EXISTS uname TEXT,
    ADD COLUMN IF NOT EXISTS language TEXT;

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
    WITH new_host AS (
        INSERT INTO host(
                         tenant_customer_id,
                         name
            )
            SELECT NEW.tenant_customer_id, * FROM UNNEST(NEW.hosts) AS name
            ON CONFLICT (tenant_customer_id,name) DO UPDATE SET name = EXCLUDED.name
            RETURNING id
    ) INSERT INTO domain_host(
        domain_id,
        host_id
    ) SELECT NEW.id, id FROM new_host;

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

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

