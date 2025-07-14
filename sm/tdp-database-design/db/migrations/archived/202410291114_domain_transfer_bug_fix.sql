DROP VIEW IF EXISTS v_accreditation;
CREATE OR REPLACE VIEW v_accreditation AS
SELECT
    a.tenant_id              AS tenant_id,
    a.id                     AS accreditation_id,
    pi.id                    AS provider_instance_id,
    p.id                     AS provider_id,
    tn.name                  AS tenant_name,
    a.name                   AS accreditation_name,
    p.name                   AS provider_name,
    pi.name                  AS provider_instance_name,
    pi.is_proxy              AS is_proxy,
    a.registrar_id           AS registrar_id
FROM accreditation a
         JOIN tenant tn ON tn.id = a.tenant_id
         JOIN provider_instance pi ON pi.id=a.provider_instance_id
         JOIN provider p ON p.id = pi.provider_id
;

CREATE OR REPLACE FUNCTION validate_transfer_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data                  JSONB;
    v_transfer_domain           RECORD;
    _parent_job_id              UUID;
    _is_fee_check_allowed       BOOLEAN;
    _is_premium_domain_enabled  BOOLEAN;
    _is_transfer_is_premium     BOOLEAN;
    _domain_max_lifetime        INT;
BEGIN
    -- order information
    SELECT
        votid.*,
        TO_JSONB(a.*) AS accreditation,
        CASE
            WHEN voip.price IS NULL THEN NULL
            ELSE JSONB_BUILD_OBJECT(
                    'amount', voip.price,
                    'currency', voip.currency_type_code,
                    'fraction', voip.currency_type_fraction
                 )
            END AS price
    INTO v_transfer_domain
    FROM v_order_transfer_in_domain votid
             JOIN v_accreditation a ON a.accreditation_id = votid.accreditation_id
             LEFT JOIN v_order_item_price voip ON voip.order_item_id = votid.order_item_id
    WHERE votid.order_item_id = NEW.order_item_id;

    SELECT get_tld_setting(
                   p_key => 'tld.lifecycle.max_lifetime',
                   p_tld_id=>v_transfer_domain.tld_id,
                   p_tenant_id=>v_transfer_domain.tenant_id
           ) INTO _domain_max_lifetime;

    -- v_transfer_domain.
    v_job_data := jsonb_build_object(
            'domain_name', v_transfer_domain.domain_name,
            'order_item_plan_id', NEW.id,
            'accreditation', v_transfer_domain.accreditation,
            'tenant_customer_id', v_transfer_domain.tenant_customer_id,
            'order_metadata', v_transfer_domain.order_metadata,
            'price', v_transfer_domain.price,
            'order_type', 'transfer_in',
            'period', v_transfer_domain.transfer_period,
            'domain_max_lifetime', _domain_max_lifetime,
            'pw', v_transfer_domain.auth_info
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
            v_job_data = v_job_data || jsonb_build_object('premium_domain_enabled', _is_premium_domain_enabled);
        END IF;

        SELECT get_tld_setting(
                       p_key => 'tld.lifecycle.transfer_is_premium',
                       p_tld_id=>v_transfer_domain.tld_id,
                       p_tenant_id=>v_transfer_domain.tenant_id
               ) INTO _is_transfer_is_premium;

        IF _is_transfer_is_premium IS NOT NULL THEN
            v_job_data = v_job_data || jsonb_build_object('premium_operation', _is_transfer_is_premium);
        END IF;

        SELECT job_create(
                       v_transfer_domain.tenant_customer_id,
                       'validate_domain_transferable',
                       NEW.id,
                       v_job_data
               )INTO _parent_job_id;

        PERFORM job_submit(
                v_transfer_domain.tenant_customer_id,
                'validate_domain_premium',
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