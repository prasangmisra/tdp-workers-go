-- function: validate_create_domain_plan()
-- description: validates plan items for domain provisioning
CREATE OR REPLACE FUNCTION validate_create_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data                  JSONB;
    v_create_domain             RECORD;
    v_secdns_record_range       INT4RANGE;
    v_job_id                    UUID;
    v_claims_period             DATERANGE;
    v_date_now                  TIMESTAMP;
    _is_premium_domain_enabled  BOOLEAN;
BEGIN
    -- order information
    SELECT
        vocd.*,
        TO_JSONB(a.*) AS accreditation,
        JSONB_BUILD_OBJECT(
                'amount', voip.price,
                'currency', voip.currency_type_code,
                'fraction', voip.currency_type_fraction
        ) AS price
    INTO v_create_domain
    FROM v_order_create_domain vocd
    JOIN v_accreditation a ON a.accreditation_id = vocd.accreditation_id
    LEFT JOIN v_order_item_price voip ON voip.order_item_id = vocd.order_item_id
    WHERE vocd.order_item_id = NEW.order_item_id;

    -- Get the range of secdns records for the TLD
    SELECT get_tld_setting(
        p_key => 'tld.dns.secdns_record_count',
        p_accreditation_tld_id => v_create_domain.accreditation_tld_id
    ) INTO v_secdns_record_range;

    -- Validate domain secdns records count
    IF NOT is_create_domain_secdns_count_valid(v_create_domain, v_secdns_record_range) THEN
        UPDATE order_item_plan
        SET result_message = FORMAT('SecDNS record count must be in this range %s-%s', lower(v_secdns_record_range), upper(v_secdns_record_range) - 1),
            validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.premium_domain_enabled',
        p_tld_id=>v_create_domain.tld_id,
        p_tenant_id=>v_create_domain.tenant_id
    ) INTO _is_premium_domain_enabled;

    v_job_data := jsonb_build_object(
        'domain_name', v_create_domain.domain_name,
        'order_item_plan_id', NEW.id,
        'registration_period', v_create_domain.registration_period,
        'accreditation', v_create_domain.accreditation,
        'tenant_customer_id', v_create_domain.tenant_customer_id,
        'order_metadata', v_create_domain.order_metadata,
        'order_item_id', v_create_domain.order_item_id,
        'price', v_create_domain.price,
        'order_type', 'create',
        'premium_domain_enabled', _is_premium_domain_enabled,
        'premium_operation', _is_premium_domain_enabled
    );

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.claims_period',
        p_tld_id=>v_create_domain.tld_id,
        p_tenant_id=>v_create_domain.tenant_id
    ) INTO v_claims_period;

    IF v_claims_period IS NOT NULL THEN
        v_date_now:= NOW();
        IF v_date_now <= UPPER(v_claims_period) AND v_date_now >= LOWER(v_claims_period) THEN
            IF v_create_domain.launch_data IS NOT NULL THEN
                v_job_data = v_job_data::jsonb || ('{"launch_data":' || v_create_domain.launch_data::json || '}')::jsonb;
            END IF;
            v_job_id := job_submit(
                v_create_domain.tenant_customer_id,
                'validate_domain_claims',
                NEW.id,
                v_job_data
            );

        END IF;
    ELSE
        v_job_id := job_submit(
            v_create_domain.tenant_customer_id,
            'validate_domain_available',
            NEW.id,
            v_job_data
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_transfer_domain_plan()
-- description: validates plan items for domain transfer
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
        'domain_max_lifetime', _domain_max_lifetime
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
            v_job_data = v_job_data::jsonb || ('{"premium_operation":' || _is_transfer_is_premium || '}' )::jsonb;
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


-- function: validate_renew_domain_plan()
-- description: validates plan items for domain renew
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
            v_job_data = v_job_data::jsonb || ('{"premium_operation":' || _is_renew_is_premium || '}' )::jsonb;
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


-- function: validate_redeem_domain_plan()
-- description: validates plan items for domain redeem
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
            v_job_data = v_job_data::jsonb || ('{"premium_operation":' || _is_redeem_is_premium || '}' )::jsonb;
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
