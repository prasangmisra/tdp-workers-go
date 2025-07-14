-- Add new job type for domain renewal
INSERT INTO job_type(
    name,
    descr,
    reference_status_table,
    reference_status_column,
    routing_key
) VALUES (
    'provision_domain_expiry_date_check',
    'Check if domain expiry date is mismatched in backend',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
) ON CONFLICT DO NOTHING;

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

-- function: provision_domain_renew_job()
-- description: creates the job to renew the domain
CREATE OR REPLACE FUNCTION provision_domain_renew_job() RETURNS TRIGGER AS $$
DECLARE
    v_renew        RECORD;
    _parent_job_id UUID;
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

    PERFORM job_submit(
            v_renew.tenant_customer_id,
            'provision_domain_expiry_date_check',
            NEW.id,
            TO_JSONB(v_renew.*),
            _parent_job_id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
