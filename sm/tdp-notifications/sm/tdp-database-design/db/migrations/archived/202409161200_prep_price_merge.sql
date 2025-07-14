ALTER TABLE currency RENAME TO currency_type;

ALTER TABLE order_item_price DROP CONSTRAINT order_price_currency_id_fkey;

ALTER TABLE order_item_price RENAME COLUMN currency_id TO currency_type_id;

ALTER TABLE order_item_price
ADD CONSTRAINT order_item_price_currency_type_id_fkey
FOREIGN KEY (currency_type_id)
REFERENCES currency_type(id);

DROP VIEW IF EXISTS v_order_item_price;
CREATE OR REPLACE VIEW v_order_item_price AS
SELECT
    oip.order_item_id,
    oip.order_id,
    oip.price,
    c.id AS currency_type_id,
    c.name AS currency_type_code,
    c.descr AS currency_type_descr,
    c.fraction AS currency_type_fraction,
    o.tenant_customer_id,
    p.name AS product_name,
    ot.name AS order_type_name
FROM order_item_price oip
JOIN currency_type c ON c.id = oip.currency_type_id
JOIN "order" o ON o.id=oip.order_id
JOIN order_type ot ON ot.id = o.type_id 
JOIN product p ON p.id=ot.product_id;


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
                        'currency', voip.currency_type_code,
                        'fraction', voip.currency_type_fraction
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

CREATE OR REPLACE FUNCTION provision_domain_renew_job() RETURNS TRIGGER AS $$
DECLARE
    v_renew     RECORD;
BEGIN
    WITH price AS (
        SELECT
            JSONB_BUILD_OBJECT(
                    'amount', voip.price,
                    'currency', voip.currency_type_code,
                    'fraction', voip.currency_type_fraction
            ) AS data
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
        pr.period  AS period,
        price.data AS price,
        pr.order_metadata AS metadata
    INTO v_renew
    FROM provision_domain_renew pr
             LEFT JOIN price ON TRUE
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pr.id = NEW.id;
    UPDATE provision_domain_renew SET job_id=job_submit(
            v_renew.tenant_customer_id,
            'provision_domain_renew',
            NEW.id,
            TO_JSONB(v_renew.*)
                                             ) WHERE id = NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION provision_domain_redeem_job() RETURNS TRIGGER AS $$
DECLARE
    v_redeem                      RECORD;
    v_domain                      RECORD;
    _parent_job_id                UUID;
    _is_redeem_report_required    BOOLEAN;
BEGIN
    WITH contacts AS (
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
                JSONB_BUILD_OBJECT(
                        'amount', voip.price,
                        'currency', voip.currency_type_code,
                        'fraction', voip.currency_type_fraction
                ) AS data
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
        pr.order_metadata AS metadata
    INTO v_redeem
    FROM provision_domain_redeem pr
             JOIN contacts ON TRUE
             JOIN hosts ON TRUE
             LEFT JOIN price ON TRUE
             JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
             JOIN domain d ON d.id=pr.domain_id
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

    IF _is_redeem_report_required THEN
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
                TO_JSONB(v_redeem.*),
                _parent_job_id
                );
    ELSE
        UPDATE provision_domain_redeem SET job_id=job_submit(
                v_redeem.tenant_customer_id,
                'provision_domain_redeem',
                NEW.id,
                TO_JSONB(v_redeem.*)
                                                  ) WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_transfer_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data                  JSONB;
    v_transfer_domain           RECORD;
    _parent_job_id              UUID;
    _is_fee_check_allowed       BOOLEAN;
    _is_premium_domain_enabled  BOOLEAN;
    _is_transfer_is_premium     BOOLEAN;
BEGIN
    -- order information
    SELECT
        votid.*,
        TO_JSONB(a.*) AS accreditation,
        JSONB_BUILD_OBJECT(
                'amount', voip.price,
                'currency', voip.currency_type_code,
                'fraction', voip.currency_type_fraction
        ) AS price
    INTO v_transfer_domain
    FROM v_order_transfer_in_domain votid
    JOIN v_accreditation a ON a.accreditation_id = votid.accreditation_id
    LEFT JOIN v_order_item_price voip ON voip.order_item_id = votid.order_item_id
    WHERE votid.order_item_id = NEW.order_item_id;

    -- v_transfer_domain.
    v_job_data := jsonb_build_object(
        'domain_name', v_transfer_domain.domain_name,
        'order_item_plan_id', NEW.id,
        'accreditation', v_transfer_domain.accreditation,
        'tenant_customer_id', v_transfer_domain.tenant_customer_id,
        'order_metadata', v_transfer_domain.order_metadata,
        'price', v_transfer_domain.price,
        'order_type', 'transfer_in'
    );

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.fee_check_allowed',
        p_tld_id=>v_transfer_domain.tld_id,
        p_tenant_id=>v_transfer_domain.tenant_id
    ) INTO _is_fee_check_allowed;

    IF _is_fee_check_allowed THEN
        SELECT get_tld_setting(
            p_key => 'tld.lifecycle.premium_domain_enabled',
            p_tld_id=>v_transfer_domain.tld_id,
            p_tenant_id=>v_transfer_domain.tenant_id
        ) INTO _is_premium_domain_enabled;

        IF _is_premium_domain_enabled IS NOT NULL THEN
            v_job_data = v_job_data::jsonb || ('{"premium_domain_enabled":' || _is_premium_domain_enabled || '}' )::jsonb;
        END IF;

        SELECT get_tld_setting(
            p_key => 'tld.lifecycle.transfer_is_premium',
            p_tld_id=>v_transfer_domain.tld_id,
            p_tenant_id=>v_transfer_domain.tenant_id
        ) INTO _is_transfer_is_premium;

        IF _is_transfer_is_premium IS NOT NULL THEN
            v_job_data = v_job_data::jsonb || ('{"transfer_is_premium":' || _is_transfer_is_premium || '}' )::jsonb;
        END IF;

        SELECT job_submit(
            v_transfer_domain.tenant_customer_id,
            'validate_domain_premium',
            NEW.id,
            v_job_data
        ) INTO _parent_job_id;
    END IF;

    IF _parent_job_id IS NOT NULL THEN
        PERFORM job_create(
            v_transfer_domain.tenant_customer_id,
            'validate_domain_transferable',
            NULL,
            v_job_data,
            _parent_job_id
        );

    ELSE
        PERFORM job_submit(
            v_transfer_domain.tenant_customer_id,
            'validate_domain_transferable',
            NEW.id,
            v_job_data
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_renew_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data                  JSONB;
    v_renew_domain              RECORD;
    _is_fee_check_allowed       BOOLEAN;
    _is_premium_domain_enabled  BOOLEAN;
    _is_renew_is_premium        BOOLEAN;
BEGIN
    -- order information
    SELECT
        votid.*,
        TO_JSONB(a.*) AS accreditation,
        JSONB_BUILD_OBJECT(
                'amount', voip.price,
                'currency', voip.currency_type_code,
                'fraction', voip.currency_type_fraction
        ) AS price
    INTO v_renew_domain
    FROM v_order_renew_domain votid
    JOIN v_accreditation a ON a.accreditation_id = votid.accreditation_id
    LEFT JOIN v_order_item_price voip ON voip.order_item_id = votid.order_item_id
    WHERE votid.order_item_id = NEW.order_item_id;

    v_job_data := jsonb_build_object(
        'domain_name', v_renew_domain.domain_name,
        'order_item_plan_id', NEW.id,
        'accreditation', v_renew_domain.accreditation,
        'tenant_customer_id', v_renew_domain.tenant_customer_id,
        'order_metadata', v_renew_domain.order_metadata,
        'price', v_renew_domain.price,
        'period', v_renew_domain.period,
        'order_type', 'renew'
    );

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.fee_check_allowed',
        p_tld_id=>v_renew_domain.tld_id,
        p_tenant_id=>v_renew_domain.tenant_id
    ) INTO _is_fee_check_allowed;


    IF _is_fee_check_allowed THEN
        SELECT get_tld_setting(
            p_key => 'tld.lifecycle.premium_domain_enabled',
            p_tld_id=>v_renew_domain.tld_id,
            p_tenant_id=>v_renew_domain.tenant_id
        ) INTO _is_premium_domain_enabled;

        IF _is_premium_domain_enabled IS NOT NULL THEN
            v_job_data = v_job_data::jsonb || ('{"premium_domain_enabled":' || _is_premium_domain_enabled || '}' )::jsonb;
        END IF;

        SELECT get_tld_setting(
            p_key => 'tld.lifecycle.renew_is_premium',
            p_tld_id=>v_renew_domain.tld_id,
            p_tenant_id=>v_renew_domain.tenant_id
        ) INTO _is_renew_is_premium;

        IF _is_renew_is_premium IS NOT NULL THEN
            v_job_data = v_job_data::jsonb || ('{"renew_is_premium":' || _is_renew_is_premium || '}' )::jsonb;
        END IF;

        PERFORM job_submit(
            v_renew_domain.tenant_customer_id,
            'validate_domain_premium',
            NEW.id,
            v_job_data
        );
    ELSE
        -- If fee check is not allowed, mark the validation status as completed
        UPDATE renew_domain_plan
        SET validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_redeem_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data                  JSONB;
    v_redeem_domain             RECORD;
    _is_fee_check_allowed       BOOLEAN;
    _is_premium_domain_enabled  BOOLEAN;
    _is_redeem_is_premium       BOOLEAN;
BEGIN
    -- order information
    SELECT
        votid.*,
        TO_JSONB(a.*) AS accreditation,
        JSONB_BUILD_OBJECT(
                'amount', voip.price,
                'currency', voip.currency_type_code,
                'fraction', voip.currency_type_fraction
        ) AS price
    INTO v_redeem_domain
    FROM v_order_redeem_domain votid
    JOIN v_accreditation a ON a.accreditation_id = votid.accreditation_id
    LEFT JOIN v_order_item_price voip ON voip.order_item_id = votid.order_item_id
    WHERE votid.order_item_id = NEW.order_item_id;

    v_job_data := jsonb_build_object(
            'domain_name', v_redeem_domain.domain_name,
            'order_item_plan_id', NEW.id,
            'accreditation', v_redeem_domain.accreditation,
            'tenant_customer_id', v_redeem_domain.tenant_customer_id,
            'order_metadata', v_redeem_domain.order_metadata,
            'price', v_redeem_domain.price,
            'order_type', 'redeem'
                  );

    SELECT get_tld_setting(
                   p_key => 'tld.lifecycle.fee_check_allowed',
                   p_tld_id=>v_redeem_domain.tld_id,
                   p_tenant_id=>v_redeem_domain.tenant_id
           ) INTO _is_fee_check_allowed;

    IF _is_fee_check_allowed THEN
        SELECT get_tld_setting(
                       p_key => 'tld.lifecycle.premium_domain_enabled',
                       p_tld_id=>v_redeem_domain.tld_id,
                       p_tenant_id=>v_redeem_domain.tenant_id
               ) INTO _is_premium_domain_enabled;

        IF _is_premium_domain_enabled IS NOT NULL THEN
            v_job_data = v_job_data::jsonb || ('{"premium_domain_enabled":' || _is_premium_domain_enabled || '}' )::jsonb;
        END IF;

        SELECT get_tld_setting(
                       p_key => 'tld.lifecycle.redeem_is_premium',
                       p_tld_id=>v_redeem_domain.tld_id,
                       p_tenant_id=>v_redeem_domain.tenant_id
               ) INTO _is_redeem_is_premium;

        IF _is_redeem_is_premium IS NOT NULL THEN
            v_job_data = v_job_data::jsonb || ('{"redeem_is_premium":' || _is_redeem_is_premium || '}' )::jsonb;
        END IF;

        PERFORM job_submit(
                v_redeem_domain.tenant_customer_id,
                'validate_domain_premium',
                NEW.id,
                v_job_data
                );
    ELSE
        -- If fee check is not allowed, mark the validation status as completed
        UPDATE redeem_domain_plan
        SET validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;