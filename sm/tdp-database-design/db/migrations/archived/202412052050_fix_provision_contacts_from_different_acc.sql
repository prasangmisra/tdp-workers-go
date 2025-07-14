CREATE OR REPLACE FUNCTION provision_domain_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
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

    UPDATE provision_domain SET job_id = job_submit(
            v_domain.tenant_customer_id,
            'provision_domain_create',
            NEW.id,
            TO_JSONB(v_domain.*)
                                         ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
