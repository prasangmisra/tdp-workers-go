-- function: provision_domain_update_job()
-- description: creates the job to update the domain.
CREATE OR REPLACE FUNCTION provision_domain_update_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
    _parent_job_id      UUID;
    v_locks_required_changes JSONB;
BEGIN
    WITH contacts AS(
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                    'type', ct.name,
                    'handle', pc.handle
            )
        ) AS data
        FROM provision_domain_update_contact pdc
            JOIN domain_contact_type ct ON ct.id = pdc.contact_type_id
            JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
            JOIN provision_status ps ON ps.id = pc.status_id
        WHERE
            ps.is_success AND ps.is_final AND pc.accreditation_id = NEW.accreditation_id
            AND pdc.provision_domain_update_id = NEW.id
    ), hosts_add AS(
        SELECT JSONB_AGG(data) AS add
        FROM (
            SELECT
                JSON_BUILD_OBJECT(
                    'name', h.name,
                    'ip_addresses', JSONB_AGG(ha.address)
                ) AS data
            FROM provision_domain_update_add_host pduah
                JOIN ONLY host h ON h.id = pduah.host_id
                LEFT JOIN ONLY host_addr ha ON h.id = ha.host_id
            WHERE pduah.provision_domain_update_id = NEW.id
            GROUP BY h.name
        ) sub_q
    ), hosts_rem AS(
        SELECT  JSONB_AGG(data) AS rem
        FROM (
            SELECT 
                JSON_BUILD_OBJECT(
                    'name', h.name,
                    'ip_addresses', JSONB_AGG(ha.address)
                ) AS data
            FROM provision_domain_update_rem_host pdurh
                JOIN ONLY host h ON h.id = pdurh.host_id
                LEFT JOIN ONLY host_addr ha ON h.id = ha.host_id
            WHERE pdurh.provision_domain_update_id = NEW.id
            GROUP BY h.name
        ) sub_q
    ), secdns_add AS(
        SELECT
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'key_tag', osdd.key_tag,
                    'algorithm', osdd.algorithm,
                    'digest_type', osdd.digest_type,
                    'digest', osdd.digest,
                    'key_data',
                    CASE
                        WHEN osdd.key_data_id IS NOT NULL THEN
                            JSONB_BUILD_OBJECT(
                                'flags', oskd2.flags,
                                'protocol', oskd2.protocol,
                                'algorithm', oskd2.algorithm,
                                'public_key', oskd2.public_key
                            )
                    END
                )
            ) FILTER (WHERE udas.ds_data_id IS NOT NULL) AS ds_data,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'flags', oskd1.flags,
                    'protocol', oskd1.protocol,
                    'algorithm', oskd1.algorithm,
                    'public_key', oskd1.public_key
                )
            ) FILTER (WHERE udas.key_data_id IS NOT NULL) AS key_data
        FROM provision_domain_update_add_secdns pduas
            LEFT JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
            LEFT JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
            LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = udas.key_data_id
            LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id

        WHERE pduas.provision_domain_update_id = NEW.id
        GROUP BY pduas.provision_domain_update_id
    ), secdns_rem AS(
        SELECT
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'key_tag', osdd.key_tag,
                    'algorithm', osdd.algorithm,
                    'digest_type', osdd.digest_type,
                    'digest', osdd.digest,
                    'key_data',
                    CASE
                        WHEN osdd.key_data_id IS NOT NULL THEN
                            JSONB_BUILD_OBJECT(
                                'flags', oskd2.flags,
                                'protocol', oskd2.protocol,
                                'algorithm', oskd2.algorithm,
                                'public_key', oskd2.public_key
                            )
                    END
                )
            ) FILTER (WHERE udrs.ds_data_id IS NOT NULL) AS ds_data,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'flags', oskd1.flags,
                    'protocol', oskd1.protocol,
                    'algorithm', oskd1.algorithm,
                    'public_key', oskd1.public_key
                )
            ) FILTER (WHERE udrs.key_data_id IS NOT NULL) AS key_data
        FROM provision_domain_update_rem_secdns pdurs
            LEFT JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            LEFT JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
            LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = udrs.key_data_id
            LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id

        WHERE pdurs.provision_domain_update_id = NEW.id
        GROUP BY pdurs.provision_domain_update_id
    )
    SELECT
        NEW.id AS provision_domain_update_id,
        tnc.id AS tenant_customer_id,
        d.order_metadata,
        d.domain_name AS name,
        d.auth_info AS pw,
        contacts.data AS contacts,
        TO_JSONB(hosts_add) || TO_JSONB(hosts_rem) AS nameservers,
        JSONB_BUILD_OBJECT(
            'max_sig_life', d.secdns_max_sig_life,
            'add', TO_JSONB(secdns_add),
            'rem', TO_JSONB(secdns_rem)
        ) as secdns,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS metadata,
        va1.value::BOOL AS is_rem_update_lock_with_domain_content_supported,
        va2.value::BOOL AS is_add_update_lock_with_domain_content_supported
    INTO v_domain
    FROM provision_domain_update d
        LEFT JOIN contacts ON TRUE
        LEFT JOIN hosts_add ON TRUE
        LEFT JOIN hosts_rem ON TRUE
        LEFT JOIN secdns_add ON TRUE
        LEFT JOIN secdns_rem ON TRUE
        JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
        JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
        JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
        JOIN v_attribute va1 ON
            va1.tld_id = vat.tld_id AND
            va1.key = 'tld.order.is_rem_update_lock_with_domain_content_supported' AND
            va1.tenant_id = tnc.tenant_id
        JOIN v_attribute va2 ON
            va2.tld_id = vat.tld_id AND
            va2.key = 'tld.order.is_add_update_lock_with_domain_content_supported' AND
            va2.tenant_id = tnc.tenant_id
    WHERE d.id = NEW.id;

    -- Retrieves the required changes for domain locks based on the provided lock configuration.
    SELECT
        JSONB_OBJECT_AGG(
                l.key, l.value::BOOLEAN
        )
    INTO v_locks_required_changes
    FROM JSONB_EACH(NEW.locks) l
             LEFT JOIN v_domain_lock vdl ON vdl.name = l.key AND vdl.domain_id = NEW.domain_id AND NOT vdl.is_internal
    WHERE (NOT l.value::boolean AND vdl.id IS NOT NULL) OR (l.value::BOOLEAN AND vdl.id IS NULL);

    -- If there are required changes for the 'update' lock AND there are other changes to the domain, THEN we MAY need to
    -- create two separate jobs: One job for the 'update' lock and Another job for all other domain changes, Because if
    -- the only change we have is 'update' lock, we can do it in a single job
    IF (v_locks_required_changes ? 'update') AND
       (COALESCE(v_domain.contacts,v_domain.nameservers,v_domain.pw::JSONB)  IS NOT NULL
           OR NOT is_jsonb_empty_or_null(v_locks_required_changes - 'update'))
    THEN
        -- If 'update' lock has false value (remove the lock) and the registry "DOES NOT" support removing that lock with
        -- the other domain changes in a single command, then we need to create two jobs: the first one to remove the
        -- domain lock, and the second one to handle the other domain changes
        IF (v_locks_required_changes->'update')::BOOLEAN IS FALSE AND
           NOT v_domain.is_rem_update_lock_with_domain_content_supported THEN
            -- all the changes without the update lock removal, because first we need to remove the lock on update
            SELECT job_create(
                           v_domain.tenant_customer_id,
                           'provision_domain_update',
                           NEW.id,
                           TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes - 'update')
                   ) INTO _parent_job_id;

            -- Update provision_domain_update table with parent job id
            UPDATE provision_domain_update SET job_id = _parent_job_id  WHERE id=NEW.id;

            -- first remove the update lock so we can do the other changes
            PERFORM job_submit(
                    v_domain.tenant_customer_id,
                    'provision_domain_update',
                    NULL,
                    jsonb_build_object('locks', jsonb_build_object('update', FALSE),
                                       'name',v_domain.name,
                                       'accreditation',v_domain.accreditation,
                                       'accreditation_tld', v_domain.accreditation_tld),
                    _parent_job_id
                    );
            RETURN NEW; -- RETURN

        -- Same thing here, if 'update' lock has true value (add the lock) and the registry DOES NOT support adding that
        -- lock with the other domain changes in a single command, then we need to create two jobs: the first one to
        -- handle the other domain changes and the second one to add the domain lock

        elsif (v_locks_required_changes->'update')::BOOLEAN IS TRUE AND
              NOT v_domain.is_add_update_lock_with_domain_content_supported THEN
            -- here we want to add the lock on update (we will do the changes first then add the lock)
            SELECT job_create(
                           v_domain.tenant_customer_id,
                           'provision_domain_update',
                           NEW.id,
                           jsonb_build_object('locks', jsonb_build_object('update', TRUE),
                                              'name',v_domain.name,
                                              'accreditation',v_domain.accreditation)
                   ) INTO _parent_job_id;

            -- Update provision_domain_update table with parent job id
            UPDATE provision_domain_update SET job_id = _parent_job_id  WHERE id=NEW.id;

            -- Submit child job for all the changes other than domain update lock
            PERFORM job_submit(
                    v_domain.tenant_customer_id,
                    'provision_domain_update',
                    NULL,
                    TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes - 'update'),
                    _parent_job_id
                    );

            RETURN NEW; -- RETURN
        end if;
    end if;
    UPDATE provision_domain_update SET
        job_id = job_submit(
                v_domain.tenant_customer_id,
                'provision_domain_update',
                NEW.id,
                TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes)
                 ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
DECLARE
    _key   text;
    _value BOOLEAN;
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
        WHERE pdc.provision_domain_update_id = NEW.id AND pc.accreditation_id = NEW.accreditation_id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
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
        FOR _key, _value IN SELECT * FROM jsonb_each_text(NEW.locks)
            LOOP
                IF _value THEN
                    INSERT INTO domain_lock(domain_id,type_id) VALUES
                        (NEW.domain_id,(SELECT id FROM lock_type where name=_key)) ON CONFLICT DO NOTHING ;

                ELSE
                    DELETE FROM domain_lock WHERE domain_id=NEW.domain_id AND
                        type_id=tc_id_from_name('lock_type',_key);
                end if;
            end loop;
    end if;


    -- remove secdns data

    WITH secdns_ds_data_rem AS (
        SELECT 
            secdns.ds_data_id AS id,
            secdns.ds_key_data_id AS key_data_id
        FROM provision_domain_update_rem_secdns pdurs
            JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
            LEFT JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            -- matching existing ds data (including optional ds key data) on domain
            JOIN LATERAL (
                SELECT
                    ds.domain_id,
                    ds.ds_data_id,
                    sdd.key_data_id AS ds_key_data_id
                FROM domain_secdns ds
                    JOIN secdns_ds_data sdd ON sdd.id = ds.ds_data_id
                    LEFT JOIN secdns_key_data skd ON skd.id = sdd.key_data_id
                WHERE ds.domain_id = NEW.domain_id
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
            ) secdns ON TRUE
        WHERE pdurs.provision_domain_update_id = NEW.id
    ),
    -- remove ds key data first if exists
    secdns_ds_key_data_rem AS (
        DELETE FROM ONLY secdns_key_data WHERE id IN (
            SELECT key_data_id FROM secdns_ds_data_rem WHERE key_data_id IS NOT NULL
        )
    )
    -- remove ds data if any
    DELETE FROM ONLY secdns_ds_data WHERE id IN (SELECT id FROM secdns_ds_data_rem);

    WITH secdns_key_data_rem AS (
        SELECT 
            secdns.key_data_id AS id
        FROM provision_domain_update_rem_secdns pdurs
            JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            JOIN order_secdns_key_data oskd ON oskd.id = udrs.key_data_id
            -- matching existing key data on domain
            JOIN LATERAL (
                SELECT
                    domain_id,
                    key_data_id
                FROM domain_secdns ds
                    JOIN secdns_key_data skd ON skd.id = ds.key_data_id
                WHERE ds.domain_id = NEW.domain_id
                    AND skd.flags = oskd.flags
                    AND skd.protocol = oskd.protocol
                    AND skd.algorithm = oskd.algorithm
                    AND skd.public_key = oskd.public_key
            ) secdns ON TRUE
        WHERE pdurs.provision_domain_update_id = NEW.id
    )
    -- remove key data if any
    DELETE FROM ONLY secdns_key_data WHERE id IN (SELECT id FROM secdns_key_data_rem);

    -- add secdns data

    WITH key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_key_data oskd ON oskd.id = udas.key_data_id
            WHERE pduas.provision_domain_update_id = NEW.id
        ) RETURNING id
    ), ds_key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            WHERE pduas.provision_domain_update_id = NEW.id
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
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                LEFT JOIN ds_key_data dkd ON dkd.id = osdd.key_data_Id
            WHERE pduas.provision_domain_update_id = NEW.id
        ) RETURNING id
    )
    INSERT INTO domain_secdns (
        domain_id,
        ds_data_id,
        key_data_id
    )(
        SELECT NEW.domain_id, NULL, id FROM key_data
        
        UNION ALL
        
        SELECT NEW.domain_id, id, NULL FROM ds_data
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
