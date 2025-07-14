ALTER TABLE order_item_create_domain
ADD COLUMN IF NOT EXISTS launch_data JSONB;


-- function: plan_create_domain_provision_domain()
-- description: create a domain based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain   RECORD;
    v_pd_id           UUID;
    v_parent_id       UUID;
    v_keydata_id      UUID;
    v_dsdata_id       UUID;
    r                 RECORD;
    v_locks_required_changes jsonb;
    v_order_item_plan_ids UUID[];
BEGIN
    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    WITH pd_ins AS (
        INSERT INTO provision_domain(
            domain_name,
            registration_period,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            auto_renew,
            secdns_max_sig_life,
            pw,
            tags,
            metadata,
            launch_data,
            order_metadata
        ) VALUES(
            v_create_domain.domain_name,
            v_create_domain.registration_period,
            v_create_domain.accreditation_id,
            v_create_domain.accreditation_tld_id,
            v_create_domain.tenant_customer_id,
            v_create_domain.auto_renew,
            v_create_domain.secdns_max_sig_life,
            COALESCE(v_create_domain.auth_info, TC_GEN_PASSWORD(16)),
            COALESCE(v_create_domain.tags,ARRAY[]::TEXT[]),
            COALESCE(v_create_domain.metadata, '{}'::JSONB),
            COALESCE(v_create_domain.launch_data, '{}'::JSONB),
            v_create_domain.order_metadata
        ) RETURNING id
    )
    SELECT id INTO v_pd_id FROM pd_ins;

    SELECT
        jsonb_object_agg(key, value)
    INTO v_locks_required_changes FROM jsonb_each(v_create_domain.locks) WHERE value::BOOLEAN = TRUE;

    IF NOT is_jsonb_empty_or_null(v_locks_required_changes) THEN
        WITH inserted_domain_update AS (
            INSERT INTO provision_domain_update(
                domain_name,
                accreditation_id,
                accreditation_tld_id,
                tenant_customer_id,
                order_metadata,
                order_item_plan_ids,
                locks
            ) VALUES (
                v_create_domain.domain_name,
                v_create_domain.accreditation_id,
                v_create_domain.accreditation_tld_id,
                v_create_domain.tenant_customer_id,
                v_create_domain.order_metadata,
                ARRAY[NEW.id],
                v_locks_required_changes
            ) RETURNING id
        )
        SELECT id INTO v_parent_id FROM inserted_domain_update;
    ELSE
        v_order_item_plan_ids := ARRAY [NEW.id];
    END IF;

    -- insert contacts
    INSERT INTO provision_domain_contact(
        provision_domain_id,
        contact_id,
        contact_type_id
    ) (
        SELECT
            v_pd_id,
            order_contact_id,
            domain_contact_type_id
        FROM create_domain_contact
        WHERE create_domain_id = NEW.order_item_id
    );

    -- insert hosts
    INSERT INTO provision_domain_host(
        provision_domain_id,
        host_id
    ) (
        SELECT
            v_pd_id,
            h.id
        FROM ONLY host h
                 JOIN order_host oh ON oh.name = h.name
                 JOIN create_domain_nameserver cdn ON cdn.host_id = oh.id
        WHERE cdn.create_domain_id = NEW.order_item_id AND oh.tenant_customer_id = h.tenant_customer_id
    );

    -- insert secdns
    INSERT INTO provision_domain_secdns(
        provision_domain_id,
        secdns_id
    ) (
        SELECT
            v_pd_id,
            cds.id 
        FROM create_domain_secdns cds
        WHERE cds.create_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain
    SET is_complete = TRUE, order_item_plan_ids = v_order_item_plan_ids, parent_id = v_parent_id
    WHERE id = v_pd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP VIEW IF EXISTS v_order_create_domain;
CREATE OR REPLACE VIEW v_order_create_domain AS
SELECT 
  cd.id AS order_item_id,
  cd.order_id AS order_id,
  cd.accreditation_tld_id,
  o.metadata AS order_metadata,
  o.tenant_customer_id,
  o.type_id,
  o.customer_user_id,
  o.status_id,
  s.name AS status_name,
  s.descr AS status_descr,
  tc.tenant_id,
  tc.customer_id,
  tc.tenant_name,
  tc.name,
  at.provider_name,
  at.provider_instance_id,
  at.provider_instance_name,
  at.tld_id AS tld_id,
  at.tld_name AS tld_name,
  at.accreditation_id,
  cd.name AS domain_name,
  cd.registration_period AS registration_period,
  cd.auto_renew,
  cd.locks,
  cd.launch_data,
  cd.auth_info,
  cd.secdns_max_sig_life,
  cd.created_date,
  cd.updated_date,
  cd.tags,
  cd.metadata
FROM order_item_create_domain cd
  JOIN "order" o ON o.id=cd.order_id  
  JOIN v_order_type ot ON ot.id = o.type_id
  JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
  JOIN order_status s ON s.id = o.status_id
  JOIN v_accreditation_tld at ON at.accreditation_tld_id = cd.accreditation_tld_id    
;

ALTER TABLE provision_domain
ADD COLUMN IF NOT EXISTS launch_data JSONB;

-- function: provision_domain_job()
-- description: creates the job to create the domain
CREATE OR REPLACE FUNCTION provision_domain_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
BEGIN
    WITH contacts AS (
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
            ps.is_success AND ps.is_final
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
                JSONB_BUILD_OBJECT(
                        'amount', voip.price,
                        'currency', voip.currency_code,
                        'fraction', voip.currency_fraction
                ) AS data
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

    UPDATE provision_domain SET job_id = job_submit(
                v_domain.tenant_customer_id,
                'provision_domain_create',
                NEW.id,
                TO_JSONB(v_domain.*)
                 ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;