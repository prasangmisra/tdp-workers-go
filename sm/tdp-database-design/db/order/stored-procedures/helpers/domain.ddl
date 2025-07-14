-- function: is_create_domain_secdns_count_valid()
-- description: validates the number of secdns records for a domain secdns create order
CREATE OR REPLACE FUNCTION is_create_domain_secdns_count_valid(v_create_domain RECORD, v_secdns_record_range INT4RANGE) RETURNS BOOLEAN AS $$
DECLARE
    v_secdns_record_count   INT;
BEGIN
    -- Get SecDNS records total count
    SELECT COUNT(*)
    INTO v_secdns_record_count
    FROM create_domain_secdns
    WHERE create_domain_id = v_create_domain.order_item_id;

    -- Check if the number of secdns records is within the allowed range
    RETURN v_secdns_record_range @> v_secdns_record_count;
END;
$$ LANGUAGE plpgsql;


-- function: is_update_domain_secdns_count_valid()
-- description: validates the number of secdns records for a domain secdns update order
CREATE OR REPLACE FUNCTION is_update_domain_secdns_count_valid(v_update_domain RECORD, v_secdns_record_range INT4RANGE) RETURNS BOOLEAN AS $$
DECLARE
    v_secdns_record_count   INT;
BEGIN
    -- Get SecDNS records total count
    WITH cur_count AS (
        SELECT
            COUNT(ds.*) AS cnt
        FROM domain_secdns ds
        WHERE ds.domain_id = v_update_domain.domain_id
    ), to_be_added AS (
        SELECT
            COUNT(udas.*) AS cnt
        FROM update_domain_add_secdns udas
        WHERE udas.update_domain_id = v_update_domain.order_item_id
    ), to_be_removed AS (
        SELECT
            COUNT(*) AS cnt
        FROM update_domain_rem_secdns udrs
        WHERE udrs.update_domain_id = v_update_domain.order_item_id
    )
    SELECT
        (SELECT cnt FROM cur_count) +
        (SELECT cnt FROM to_be_added) -
        (SELECT cnt FROM to_be_removed)
    INTO v_secdns_record_count;

    -- Check if the number of secdns records is within the allowed range
    RETURN v_secdns_record_range @> v_secdns_record_count;
END;
$$ LANGUAGE plpgsql;


-- function: is_contact_type_supported_for_tld()
-- description: validates the domain contact type
CREATE OR REPLACE FUNCTION is_contact_type_supported_for_tld(contact_type_id UUID, accreditation_tld_id UUID) RETURNS BOOLEAN AS $$
DECLARE
    v_required_contact_types TEXT[];
    v_optional_contact_types TEXT[];
    v_contact_type           TEXT;
BEGIN
    -- Get contact type name
    SELECT tc_name_from_id('domain_contact_type', contact_type_id) INTO v_contact_type;

    -- Get required and optional contact types for the TLD
    SELECT
        get_tld_setting(p_key => 'tld.contact.required_contact_types', p_accreditation_tld_id => accreditation_tld_id) AS v_required_contact_types,
        get_tld_setting(p_key => 'tld.contact.optional_contact_types', p_accreditation_tld_id => accreditation_tld_id) AS v_optional_contact_types
    INTO 
        v_required_contact_types, 
        v_optional_contact_types;

    -- Check if the contact type is valid
    RETURN v_contact_type = ANY(ARRAY_CAT(v_required_contact_types, v_optional_contact_types));
END;
$$ LANGUAGE plpgsql;

-- function: update_domain_locks()
-- description: updates the locks for a domain
CREATE OR REPLACE FUNCTION update_domain_locks(v_domain_id UUID, v_locks JSONB) RETURNS VOID AS $$
DECLARE
    _lock   TEXT;
    _is_set BOOLEAN;
BEGIN
    FOR _lock, _is_set IN SELECT * FROM jsonb_each_text(v_locks)
    LOOP
        IF _is_set THEN
            INSERT INTO domain_lock(domain_id, type_id)
            VALUES (v_domain_id, tc_id_from_name('lock_type', _lock))
            ON CONFLICT DO NOTHING;
        ELSE
            DELETE FROM domain_lock
            WHERE domain_id = v_domain_id
            AND type_id = tc_id_from_name('lock_type', _lock);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- function: remove_domain_secdns_data()
-- description: removes secdns data for a domain
CREATE OR REPLACE FUNCTION remove_domain_secdns_data(v_domain_id UUID, v_update_domain_rem_secdns_ids UUID[]) RETURNS VOID AS $$
BEGIN
    WITH secdns_ds_data_rem AS (
        SELECT 
            ds.ds_data_id AS id,
            sdd.key_data_id AS key_data_id
        FROM update_domain_rem_secdns udrs
        -- join data in order
        JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
        LEFT JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
        -- join data in domain
        JOIN domain_secdns ds ON ds.domain_id = v_domain_id
        JOIN secdns_ds_data sdd ON sdd.id = ds.ds_data_id
        LEFT JOIN secdns_key_data skd ON skd.id = sdd.key_data_id
        WHERE udrs.id = ANY(v_update_domain_rem_secdns_ids)
            -- find matching data
            AND sdd.key_tag = osdd.key_tag
            AND sdd.algorithm = osdd.algorithm
            AND sdd.digest_type = osdd.digest_type
            AND sdd.digest = osdd.digest
            AND (
                (sdd.key_data_id IS NULL AND osdd.key_data_id IS NULL)
                OR
                (
                    skd.flags = oskd.flags
                    AND skd.protocol = oskd.protocol
                    AND skd.algorithm = oskd.algorithm
                    AND skd.public_key = oskd.public_key
                )
            )
    ),
    -- remove ds key data first if exists
    secdns_ds_key_data_rem AS (
        DELETE FROM ONLY secdns_key_data WHERE id IN (
            SELECT key_data_id FROM secdns_ds_data_rem WHERE key_data_id IS NOT NULL
        )
    )
    -- remove secdns ds data if any
    DELETE FROM ONLY secdns_ds_data WHERE id IN (SELECT id FROM secdns_ds_data_rem);

    -- remove secdns key data if any
    DELETE FROM ONLY secdns_key_data
    WHERE id IN (
        SELECT skd.id
        FROM update_domain_rem_secdns udrs
        JOIN order_secdns_key_data oskd ON oskd.id = udrs.key_data_id
        JOIN domain_secdns ds ON ds.domain_id = v_domain_id
        JOIN secdns_key_data skd ON skd.id = ds.key_data_id
        WHERE udrs.id  = ANY(v_update_domain_rem_secdns_ids)
          AND skd.flags = oskd.flags
          AND skd.protocol = oskd.protocol
          AND skd.algorithm = oskd.algorithm
          AND skd.public_key = oskd.public_key
    );

END;
$$ LANGUAGE plpgsql;


-- function: add_domain_secdns_data()
-- description: adds secdns data for a domain
CREATE OR REPLACE FUNCTION add_domain_secdns_data(v_domain_id UUID, v_update_domain_add_secdns_ids UUID[]) RETURNS VOID AS $$
BEGIN
    WITH key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM update_domain_add_secdns udas
                JOIN order_secdns_key_data oskd ON oskd.id = udas.key_data_id
            WHERE udas.id = ANY(v_update_domain_add_secdns_ids)
        ) RETURNING id
    ), ds_key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM update_domain_add_secdns udas
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            WHERE udas.id = ANY(v_update_domain_add_secdns_ids)
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
            FROM update_domain_add_secdns udas
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                LEFT JOIN ds_key_data dkd ON dkd.id = osdd.key_data_Id
            WHERE udas.id = ANY(v_update_domain_add_secdns_ids)
        ) RETURNING id
    )
    INSERT INTO domain_secdns (
        domain_id,
        ds_data_id,
        key_data_id
    )(
        SELECT v_domain_id, NULL, id FROM key_data
        
        UNION ALL
        
        SELECT v_domain_id, id, NULL FROM ds_data
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_random_string(length INTEGER DEFAULT 16) RETURNS TEXT AS $$
BEGIN
RETURN
(
    SELECT string_agg(
        substr(chars, trunc(random() * length(chars) + 1)::int, 1),
        ''
    )
    FROM generate_series(1, length),
    LATERAL (
        SELECT 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{}|;:,.<>?/' AS chars
    ) AS t
);
END;
$$ LANGUAGE plpgsql;
