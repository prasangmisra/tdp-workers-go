-- Add new column to the provision_domain_redeem table
ALTER TABLE provision_domain_redeem 
ADD COLUMN IF NOT EXISTS in_restore_pending_status BOOLEAN DEFAULT FALSE;

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
                TO_JSONB(v_redeem.*),
                _parent_job_id,
                _start_date
            );
    ELSE
        UPDATE provision_domain_redeem SET job_id=job_submit(
                v_redeem.tenant_customer_id,
                'provision_domain_redeem',
                NEW.id,
                TO_JSONB(v_redeem.*),
                NULL,
                _start_date
            ) WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
