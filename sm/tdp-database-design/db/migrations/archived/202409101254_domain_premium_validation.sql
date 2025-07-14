-- insert new job types for transfer processing
INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key
)
VALUES
(
    'validate_domain_premium',
    'Validates domain is premium',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobDomainProvision'
)
ON CONFLICT DO NOTHING;

-- add new tld_setting for transfer_server_auto_approve_supported
INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null
)
VALUES
(
    'fee_check_allowed',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry supports fee check',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    FALSE::TEXT,
    FALSE
),
(
    'premium_domain_enabled',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Is premium domain enabled',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    FALSE::TEXT,
    FALSE
),
(
    'renew_is_premium',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry renew is premium',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
),
(
    'redeem_is_premium',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry redeem is premium',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
),
(
    'transfer_is_premium',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry transfer is premium',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
)
ON CONFLICT DO NOTHING;

UPDATE order_item_strategy
SET is_validation_required = TRUE
WHERE order_type_id = (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='redeem')
  AND object_id = tc_id_from_name('order_item_object','domain')
  AND provision_order = 1;

UPDATE order_item_strategy
SET is_validation_required = TRUE
WHERE order_type_id = (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='renew')
  AND object_id = tc_id_from_name('order_item_object','domain')
  AND provision_order = 1;

DROP TRIGGER IF EXISTS validate_transfer_domain_plan_tg ON transfer_in_domain_plan;
DROP FUNCTION IF EXISTS validate_transfer_domain_plan;

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
BEGIN
    -- order information
    SELECT
        votid.*,
        TO_JSONB(a.*) AS accreditation,
        JSONB_BUILD_OBJECT(
                'amount', voip.price,
                'currency', voip.currency_code,
                'fraction', voip.currency_fraction
        ) AS price
    INTO v_transfer_domain
    FROM v_order_transfer_in_domain votid
    JOIN v_accreditation a ON a.accreditation_id = votid.accreditation_id
    LEFT JOIN v_order_item_price voip ON voip.order_item_id = votid.order_item_id
    WHERE votid.order_item_id = NEW.order_item_id;

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

CREATE TRIGGER validate_transfer_domain_plan_tg
    AFTER UPDATE ON transfer_in_domain_plan
    FOR EACH ROW WHEN (
    NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
        AND NEW.provision_order = 1
    )
    EXECUTE PROCEDURE validate_transfer_domain_plan();

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
                'currency', voip.currency_code,
                'fraction', voip.currency_fraction
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

CREATE TRIGGER validate_renew_domain_plan_tg
    AFTER UPDATE ON renew_domain_plan
    FOR EACH ROW WHEN (
    NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
        AND NEW.provision_order = 1
    )
    EXECUTE PROCEDURE validate_renew_domain_plan();

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
                'currency', voip.currency_code,
                'fraction', voip.currency_fraction
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

CREATE TRIGGER validate_redeem_domain_plan_tg
    AFTER UPDATE ON redeem_domain_plan
    FOR EACH ROW WHEN (
    NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
        AND NEW.provision_order = 1
    )
    EXECUTE PROCEDURE validate_redeem_domain_plan();
