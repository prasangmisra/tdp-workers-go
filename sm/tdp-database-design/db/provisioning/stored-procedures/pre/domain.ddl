-- function: provision_domain_job()
-- description: creates the job to create the domain
CREATE OR REPLACE FUNCTION provision_domain_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
    _start_date  TIMESTAMPTZ;
BEGIN
    WITH 
        contacts AS (
            SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                                'type',ct.name,
                                'handle',pc.handle
                        )
                ) AS data
            FROM provision_domain pd
                    JOIN provision_domain_contact pdc
                        ON pdc.provision_domain_id=pd.id
                    JOIN domain_contact_type ct ON ct.id=pdc.contact_type_id
                    JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
                    JOIN provision_status ps ON ps.id = pc.status_id
            WHERE
                ps.is_success AND ps.is_final AND pd.accreditation_id = pc.accreditation_id
            AND pd.id = NEW.id
        ),
        hosts AS (
            SELECT JSONB_AGG(data) AS data
            FROM
                (SELECT JSONB_BUILD_OBJECT(
                                'name',
                                h.name,
                                'ip_addresses',
                                COALESCE(jsonb_agg(ha.address) FILTER (WHERE ha.host_id IS NOT NULL), '[]')
                        ) as data
                FROM provision_domain pd
                        JOIN provision_domain_host pdh ON pdh.provision_domain_id=pd.id
                        JOIN ONLY host h ON h.id = pdh.host_id
                        -- addresses might be omitted if customer is not authoritative
                        -- or host already existed at registry
                        LEFT JOIN ONLY host_addr ha on ha.host_id = h.id 
                WHERE pd.id=NEW.id
                GROUP BY h.name) sub_q
        ),
        price AS (
            SELECT
                CASE
                    WHEN voip.price IS NULL THEN NULL
                    ELSE JSONB_BUILD_OBJECT(
                        'amount', voip.price,
                        'currency', voip.currency_type_code,
                        'fraction', voip.currency_type_fraction
                    )
                END AS data
            FROM v_order_item_price voip
                    JOIN v_order_create_domain vocd ON voip.order_item_id = vocd.order_item_id AND voip.order_id = vocd.order_id
            WHERE vocd.domain_name = NEW.domain_name
            ORDER BY vocd.created_date DESC
            LIMIT 1
        ),
        secdns AS (
            SELECT
                pd.secdns_max_sig_life as max_sig_life,
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
                ) FILTER (WHERE cds.ds_data_id IS NOT NULL) AS ds_data,
                JSONB_AGG(
                	JSONB_BUILD_OBJECT(
                    	'flags', oskd1.flags,
                   		'protocol', oskd1.protocol,
                    	'algorithm', oskd1.algorithm,
                    	'public_key', oskd1.public_key
                 	)
            	) FILTER (WHERE cds.key_data_id IS NOT NULL) AS key_data
            FROM provision_domain pd
                JOIN provision_domain_secdns pds ON pds.provision_domain_id = pd.id
                JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                LEFT JOIN order_secdns_ds_data osdd ON osdd.id = cds.ds_data_id
                LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = cds.key_data_id
                LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id
            WHERE pd.id = NEW.id
            GROUP BY pd.id, cds.create_domain_id
        )
    SELECT
        NEW.id AS provision_contact_id,
        tnc.id AS tenant_customer_id,
        d.domain_name AS name,
        d.registration_period,
        d.pw AS pw,
        contacts.data AS contacts,
        hosts.data AS nameservers,
        price.data AS price,
        CASE
            WHEN d.uname IS NULL AND d.language IS NULL
            THEN NULL
            ELSE jsonb_build_object('uname', d.uname, 'language', d.language)
        END AS idn,
        TO_JSONB(secdns.*) AS secdns,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.launch_data AS launch_data,
        d.order_metadata AS metadata
    INTO v_domain
    FROM provision_domain d
             JOIN contacts ON TRUE
             JOIN hosts ON TRUE
             LEFT JOIN price ON TRUE
             LEFT JOIN secdns ON TRUE
             JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
             JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE d.id = NEW.id;

    _start_date := job_start_date(NEW.attempt_count);

    UPDATE provision_domain SET job_id = job_submit(
            v_domain.tenant_customer_id,
            'provision_domain_create',
            NEW.id,
            TO_JSONB(v_domain.*),
            NULL,
            _start_date
    ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_renew_job()
-- description: creates the job to renew the domain
CREATE OR REPLACE FUNCTION provision_domain_renew_job() RETURNS TRIGGER AS $$
DECLARE
    v_renew        RECORD;
    _parent_job_id UUID;
    _start_date    TIMESTAMPTZ;
BEGIN
    WITH price AS (
        SELECT
            CASE
                WHEN voip.price IS NULL THEN NULL
                ELSE JSONB_BUILD_OBJECT(
                    'amount', voip.price,
                    'currency', voip.currency_type_code,
                    'fraction', voip.currency_type_fraction
                )
            END AS data
        FROM v_order_item_price voip
                 JOIN v_order_renew_domain vord ON voip.order_item_id = vord.order_item_id AND voip.order_id = vord.order_id
        WHERE vord.domain_name = NEW.domain_name
        ORDER BY vord.created_date DESC
        LIMIT 1
    )
    SELECT
        NEW.id AS provision_domain_renew_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pr.domain_name AS domain_name,
        pr.current_expiry_date AS expiry_date,
        pr.period AS period,
        price.data AS price,
        pr.order_metadata AS metadata
    INTO v_renew
    FROM provision_domain_renew pr
            LEFT JOIN price ON TRUE
            JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
            JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pr.id = NEW.id;

    SELECT job_create(
            v_renew.tenant_customer_id,
            'provision_domain_renew',
            NEW.id,
            TO_JSONB(v_renew.*) - 'period' - 'expiry_date' -- Job data should not include current expiry date and period as it might change.
        ) INTO _parent_job_id;
    
    UPDATE provision_domain_renew SET job_id = _parent_job_id WHERE id=NEW.id;

    _start_date := job_start_date(NEW.attempt_count);

    PERFORM job_submit(
            v_renew.tenant_customer_id,
            'setup_domain_renew',
            NEW.id,
            TO_JSONB(v_renew.*),
            _parent_job_id,
            _start_date
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_redeem_job()
-- description: creates the job to redeem the domain
CREATE OR REPLACE FUNCTION provision_domain_redeem_job() RETURNS TRIGGER AS $$
DECLARE
    v_redeem                      RECORD;
    v_domain                      RECORD;
    _parent_job_id                UUID;
    _is_redeem_report_required    BOOLEAN;
    _start_date                   TIMESTAMPTZ;
BEGIN
    WITH
        contacts AS (
            SELECT JSON_AGG(
                        JSONB_BUILD_OBJECT(
                                'type', dct.name,
                                'handle',dc.handle
                        )
                ) AS data
            FROM provision_domain_redeem pdr
                    JOIN domain d ON d.id = pdr.domain_id
                    JOIN domain_contact dc on dc.domain_id = d.id
                    JOIN domain_contact_type dct ON dct.id = dc.domain_contact_type_id
            WHERE pdr.id = NEW.id
        ),
        hosts AS (
            SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                                'name',
                                h.name
                        )
                ) AS data
            FROM provision_domain_redeem pdr
                    JOIN domain d ON d.id = pdr.domain_id
                    JOIN domain_host dh ON dh.domain_id = d.id
                    JOIN host h ON h.id = dh.host_id
            WHERE pdr.id = NEW.id
        ),
        price AS (
            SELECT
                CASE
                    WHEN voip.price IS NULL THEN NULL
                    ELSE JSONB_BUILD_OBJECT(
                        'amount', voip.price,
                        'currency', voip.currency_type_code,
                        'fraction', voip.currency_type_fraction
                    )
                END AS data
            FROM v_order_item_price voip
                    JOIN v_order_redeem_domain vord ON voip.order_item_id = vord.order_item_id AND voip.order_id = vord.order_id
            WHERE vord.domain_name = NEW.domain_name
            ORDER BY vord.created_date DESC
            LIMIT 1
        )
    SELECT
        d.name AS domain_name,
        'ok' AS status,
        d.deleted_date AS delete_date,
        NOW() AS restore_date,
        d.ry_expiry_date AS expiry_date,
        d.ry_created_date AS create_date,
        contacts.data AS contacts,
        hosts.data AS nameservers,
        price.data AS price,
        TO_JSONB(a.*) AS accreditation,
        tnc.id AS tenant_customer_id,
        NEW.id AS provision_domain_redeem_id,
        pr.order_metadata AS metadata,
        get_tld_setting(
            p_key=>'tld.lifecycle.restore_report_includes_fee_ext',
            p_tld_name=>vat.tld_name,
            p_tenant_id=>a.tenant_id
        )::BOOL AS restore_report_includes_fee_ext
    INTO v_redeem
    FROM provision_domain_redeem pr
    JOIN contacts ON TRUE
    JOIN hosts ON TRUE
    LEFT JOIN price ON TRUE
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    JOIN domain d ON d.id=pr.domain_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    WHERE pr.id = NEW.id;

    SELECT * INTO v_domain
    FROM domain d
    WHERE d.id=NEW.domain_id
      AND d.tenant_customer_id=NEW.tenant_customer_id;

    SELECT get_tld_setting(
                   p_key => 'tld.lifecycle.is_redeem_report_required',
                   p_tld_id=>vat.tld_id,
                   p_tenant_id=>vtc.tenant_id
           ) INTO _is_redeem_report_required
    FROM v_accreditation_tld vat
             JOIN v_tenant_customer vtc ON vtc.id = v_domain.tenant_customer_id
    WHERE vat.accreditation_tld_id = v_domain.accreditation_tld_id;

    _start_date := job_start_date(NEW.attempt_count);

    IF _is_redeem_report_required OR NEW.in_restore_pending_status THEN
        SELECT job_create(
                       v_redeem.tenant_customer_id,
                       'provision_domain_redeem_report',
                       NEW.id,
                       TO_JSONB(v_redeem.*)
               ) INTO _parent_job_id;

        UPDATE provision_domain_redeem SET job_id = _parent_job_id WHERE id=NEW.id;

        PERFORM job_submit(
                v_redeem.tenant_customer_id,
                'provision_domain_redeem',
                NULL,
                TO_JSONB(v_redeem.*) || jsonb_build_object(
                    'is_redeem_report_required', _is_redeem_report_required
                ),
                _parent_job_id,
                _start_date
            );
    ELSE
        UPDATE provision_domain_redeem SET job_id=job_submit(
                v_redeem.tenant_customer_id,
                'provision_domain_redeem',
                NEW.id,
                TO_JSONB(v_redeem.*) || jsonb_build_object(
                        'is_redeem_report_required', _is_redeem_report_required
                                        ),
                NULL,
                _start_date
            ) WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_delete_job()
-- description: creates the job to delete the domain
CREATE OR REPLACE FUNCTION provision_domain_delete_job() RETURNS TRIGGER AS $$
DECLARE
    v_delete        RECORD;
    _pddh           RECORD;
    _parent_job_id  UUID;
    _start_date     TIMESTAMPTZ;
BEGIN
    SELECT
        NEW.id AS provision_domain_delete_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pd.domain_name AS domain_name,
        pd.in_redemption_grace_period,
        pd.order_metadata AS metadata
    INTO v_delete
    FROM provision_domain_delete pd
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pd.id = NEW.id;

    SELECT job_create(
        v_delete.tenant_customer_id,
        'provision_domain_delete',
        NEW.id,
        TO_JSONB(v_delete.*)
    ) INTO _parent_job_id;

    UPDATE provision_domain_delete SET job_id= _parent_job_id WHERE id=NEW.id;

    _start_date := job_start_date(NEW.attempt_count);

    PERFORM job_submit(
        v_delete.tenant_customer_id,
        'setup_domain_delete',
        NEW.id,
        TO_JSONB(v_delete.*),
        _parent_job_id,
        _start_date
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_hosts_delete_job()
-- description: creates the job to delete the domain hosts
CREATE OR REPLACE FUNCTION provision_domain_hosts_delete_job() RETURNS TRIGGER AS $$
DECLARE
    _host_name      TEXT;
    _pddh_id        UUID;
    _pddh           RECORD;
BEGIN
    -- Validate if any of the subordinated hosts belong to customer and associated with active domains in database
    IF EXISTS (
        SELECT 1
        FROM host h
        JOIN domain_host dh ON dh.host_id = h.id
        WHERE h.name = ANY(NEW.hosts)
    ) THEN
        UPDATE job
        SET result_message = 'Host(s) are associated with active domain(s)',
            status_id = tc_id_from_name('job_status', 'failed')
        WHERE id = NEW.job_id;

        RETURN NEW;
    END IF;

    -- Insert hosts and submit job for each domain host deletion
    IF NEW.hosts IS NOT NULL THEN
        FOR _host_name IN SELECT UNNEST(NEW.hosts) LOOP
            WITH inserted AS (
                INSERT INTO provision_domain_delete_host(
                    provision_domain_delete_id,
                    host_name,
                    tenant_customer_id,
                    order_metadata
                )
                VALUES (NEW.id, _host_name, NEW.tenant_customer_id, NEW.order_metadata)
                RETURNING id
            )
            SELECT id FROM inserted INTO _pddh_id;

            SELECT
                NEW.id AS provision_domain_delete_id,
                _host_name AS host_name,
                NEW.tenant_customer_id as tenant_customer_id,
                get_tld_setting(
                    p_key=>'tld.order.host_delete_rename_allowed',
                    p_tld_name=>tld_part(_host_name),
                    p_tenant_id=>a.tenant_id
                )::BOOL AS host_delete_rename_allowed,
                get_tld_setting(
                    p_key=>'tld.order.host_delete_rename_domain',
                    p_tld_name=>tld_part(_host_name),
                    p_tenant_id=>a.tenant_id
                )::TEXT AS host_delete_rename_domain,
                TO_JSONB(a.*) AS accreditation,
                NEW.order_metadata AS metadata
            INTO _pddh
            FROM v_accreditation a
            WHERE a.accreditation_id = NEW.accreditation_id;

            UPDATE provision_domain_delete_host SET job_id=job_submit(
                NEW.tenant_customer_id,
                'provision_domain_delete_host',
                _pddh_id,
                TO_JSONB(_pddh.*),
                NEW.job_id
            )
            WHERE id = _pddh_id;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


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
    ), contacts_add AS(
        SELECT JSONB_AGG(data) AS add
        FROM (
            SELECT
                JSON_BUILD_OBJECT(
                    'type', ct.name,
                    'handle', pc.handle
                ) AS data
            FROM provision_domain_update_add_contact pduac
                JOIN domain_contact_type ct ON ct.id = pduac.contact_type_id
                JOIN provision_contact pc ON pc.contact_id = pduac.contact_id
                JOIN provision_status ps ON ps.id = pc.status_id
            WHERE
                ps.is_success AND ps.is_final AND pc.accreditation_id = NEW.accreditation_id
                AND pduac.provision_domain_update_id = NEW.id
        ) sub_q
    ), contacts_rem AS(
        SELECT JSONB_AGG(data) AS rem
        FROM (
            SELECT
                JSON_BUILD_OBJECT(
                    'type', ct.name,
                    'handle', dc.handle
                ) AS data
            FROM provision_domain_update_rem_contact pdurc
                 JOIN provision_domain_update pdu ON pdu.id = pdurc.provision_domain_update_id
                 JOIN domain_contact dc on dc.domain_id = pdu.domain_id
                    AND dc.domain_contact_type_id = pdurc.contact_type_id
                    AND dc.contact_id = pdurc.contact_id
                 JOIN domain_contact_type ct ON ct.id = pdurc.contact_type_id
            WHERE pdurc.provision_domain_update_id = NEW.id
        ) sub_q
    ),hosts_add AS(
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
        coalesce(contacts.data, TO_JSONB(contacts_add) || TO_JSONB(contacts_rem))AS contacts,
        TO_JSONB(hosts_add) || TO_JSONB(hosts_rem) AS nameservers,
        JSONB_BUILD_OBJECT(
            'max_sig_life', d.secdns_max_sig_life,
            'add', TO_JSONB(secdns_add),
            'rem', TO_JSONB(secdns_rem)
        ) as secdns,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS metadata,
        (lock_attrs.lock_support->>'tld.order.is_rem_update_lock_with_domain_content_supported')::boolean AS is_rem_update_lock_with_domain_content_supported,
        (lock_attrs.lock_support->>'tld.order.is_add_update_lock_with_domain_content_supported')::boolean AS is_add_update_lock_with_domain_content_supported
    INTO v_domain
    FROM provision_domain_update d
        LEFT JOIN contacts ON TRUE
        LEFT JOIN contacts_add ON TRUE
        LEFT JOIN contacts_rem ON TRUE
        LEFT JOIN hosts_add ON TRUE
        LEFT JOIN hosts_rem ON TRUE
        LEFT JOIN secdns_add ON TRUE
        LEFT JOIN secdns_rem ON TRUE
        JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
        JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
        JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
        JOIN LATERAL (
        SELECT jsonb_object_agg(key, value) AS lock_support
        FROM v_attribute va
        WHERE va.accreditation_tld_id = d.accreditation_tld_id
          AND va.key IN (
             'tld.order.is_rem_update_lock_with_domain_content_supported',
             'tld.order.is_add_update_lock_with_domain_content_supported'
            )
        ) lock_attrs ON true
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


-- function: provision_domain_transfer_in_request_job()
-- description: creates the job to submit transfer request for the domain
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_request_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in   RECORD;
    _start_date    TIMESTAMPTZ;
BEGIN
    WITH
        price AS (
            SELECT
                CASE
                    WHEN voip.price IS NULL THEN NULL
                    ELSE JSONB_BUILD_OBJECT(
                            'amount', voip.price,
                            'currency', voip.currency_type_code,
                            'fraction', voip.currency_type_fraction
                         )
                    END AS data
            FROM v_order_item_price voip
                     JOIN v_order_transfer_in_domain vord ON voip.order_item_id = vord.order_item_id AND voip.order_id = vord.order_id
            WHERE vord.domain_name = NEW.domain_name
            ORDER BY vord.created_date DESC
            LIMIT 1
        )
    SELECT
        NEW.id AS provision_domain_transfer_in_request_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.pw,
        pdt.transfer_period,
        pdt.order_metadata AS metadata,
        price.data AS price
    INTO v_transfer_in
    FROM provision_domain_transfer_in_request pdt
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
             LEFT JOIN price ON TRUE
    WHERE pdt.id = NEW.id;

    _start_date := job_start_date(NEW.attempt_count);

    UPDATE provision_domain_transfer_in_request SET job_id=job_submit(
        v_transfer_in.tenant_customer_id,
        'provision_domain_transfer_in_request',
        NEW.id,
        TO_JSONB(v_transfer_in.*),
        NULL,
        _start_date
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_transfer_in_job()
-- description: creates the job to fetch transferred domain data
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in  RECORD;
    _start_date    TIMESTAMPTZ;
BEGIN
    SELECT
        NEW.id AS provision_domain_transfer_in_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.order_metadata AS metadata
    INTO v_transfer_in
    FROM provision_domain_transfer_in pdt
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pdt.id = NEW.id;

    _start_date := job_start_date(NEW.attempt_count);

    UPDATE provision_domain_transfer_in SET job_id=job_submit(
        v_transfer_in.tenant_customer_id,
        'provision_domain_transfer_in',
        NEW.id,
        TO_JSONB(v_transfer_in.*),
        NULL,
        _start_date
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_transfer_away_job()
-- description: creates the job to submit transfer away action for the domain
CREATE OR REPLACE FUNCTION provision_domain_transfer_away_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_away   RECORD;
BEGIN
    SELECT
        NEW.id AS provision_domain_transfer_action_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.pw,
        pdt.order_metadata AS metadata,
        ts.name AS transfer_status
    INTO v_transfer_away
    FROM provision_domain_transfer_away pdt
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    JOIN transfer_status ts ON ts.id = NEW.transfer_status_id
    WHERE pdt.id = NEW.id;

    UPDATE provision_domain_transfer_away SET job_id=job_submit(
        v_transfer_away.tenant_customer_id,
        'provision_domain_transfer_away',
        NEW.id,
        TO_JSONB(v_transfer_away.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_transfer_in_cancel_request_job()
-- description: creates the job to cancel transfer in request for the domain
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_cancel_request_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in   RECORD;
BEGIN
    SELECT
        NEW.id AS provision_domain_transfer_action_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdtr.domain_name,
        pdtr.pw,
        pdtr.order_metadata AS metadata,
        'clientCancelled' AS transfer_status
    INTO v_transfer_in
    FROM provision_domain_transfer_in_cancel_request pdtcr
        JOIN provision_domain_transfer_in_request pdtr ON pdtr.id = pdtcr.transfer_in_request_id
        JOIN v_accreditation a ON a.accreditation_id = pdtr.accreditation_id
        JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pdtcr.id = NEW.id;

    UPDATE provision_domain_transfer_in_cancel_request SET job_id=job_submit(
        v_transfer_in.tenant_customer_id,
        'provision_domain_transfer_in_cancel_request',
        NEW.id,
        TO_JSONB(v_transfer_in.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
