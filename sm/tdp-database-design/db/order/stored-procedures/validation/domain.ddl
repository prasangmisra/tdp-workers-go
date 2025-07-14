-- function: validate_renew_order_expiry_date()
-- description: validate domain renew order data
CREATE OR REPLACE FUNCTION validate_renew_order_expiry_date() RETURNS TRIGGER AS $$
DECLARE
    v_domain RECORD;
    max_lifetime INT;
BEGIN
    -- Fetch the domain record based on the name
    SELECT * INTO v_domain
    FROM domain
    WHERE name = NEW.name;

    -- Validate the expiry date matches the stored expiry date
    IF NEW.current_expiry_date::DATE != v_domain.ry_expiry_date::DATE THEN
        RAISE EXCEPTION 'The provided expiry date % does not match the current expiry date %',
            NEW.current_expiry_date::DATE, v_domain.ry_expiry_date::DATE;
    END IF;

    SELECT get_tld_setting(
                   p_key => 'tld.lifecycle.max_lifetime',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO max_lifetime;

    -- Validate that the new renewal period doesn't exceed the maximum allowed lifetime
    IF v_domain.ry_expiry_date + (NEW.period || ' years')::INTERVAL > NOW() + (max_lifetime || ' years')::INTERVAL THEN
        RAISE EXCEPTION 'The renewal period of % years exceeds the maximum allowed lifetime of % years for the TLD',
            NEW.period, max_lifetime;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_domain_is_deleted()
-- description: check if the domain on the order data is deleted
CREATE OR REPLACE FUNCTION order_prevent_if_domain_is_deleted() RETURNS TRIGGER AS $$
BEGIN
    -- Skip the check if order type is update_internal
    PERFORM TRUE FROM v_order WHERE order_id = NEW.order_id AND product_name = 'domain' AND order_type_name = 'update_internal';

    IF FOUND THEN
        RETURN NEW;
    END IF;

    PERFORM TRUE FROM v_domain WHERE name=NEW.name and rgp_epp_status IN ('redemptionPeriod', 'pendingDelete');

    IF FOUND THEN
        RAISE EXCEPTION 'Domain ''%'' is deleted domain', NEW.name USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_domain_in_redemption_period()
-- description: validates domain in grace period
CREATE OR REPLACE FUNCTION validate_domain_in_redemption_period() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM v_domain WHERE name=NEW.name and rgp_epp_status = 'redemptionPeriod';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Domain ''%'' not in redemption grace period', NEW.name;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_domain_exists
-- description: prevents order creation if domain exists
CREATE OR REPLACE FUNCTION order_prevent_if_domain_exists() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM domain WHERE name=NEW.name LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Domain ''%'' already exists', NEW.name;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_item_check_hosting_domain_exists
-- description: prevents hosting create if hosting with same domain exists and not deleted
CREATE OR REPLACE FUNCTION order_item_check_hosting_domain_exists() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM ONLY hosting WHERE domain_name = NEW.domain_name AND NOT is_deleted;

    IF FOUND THEN
        RAISE EXCEPTION 'Hosting for ''%'' already exists', NEW.domain_name USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: order_prevent_if_domain_does_not_exist()
-- description: check if domain from order data exists
CREATE OR REPLACE FUNCTION order_prevent_if_domain_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    v_domain    RECORD;
BEGIN
    SELECT * INTO v_domain
    FROM domain d
             JOIN "order" o ON o.id=NEW.order_id
    WHERE d.name=NEW.name OR d.id=NEW.domain_id
        AND d.tenant_customer_id=o.tenant_customer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Domain ''% %'' not found', NEW.domain_id, NEW.name USING ERRCODE = 'no_data_found';
    END IF;

    NEW.domain_id = v_domain.id;
    NEW.name = v_domain.name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_domain_operation_prohibited
-- description: checks if domain operation is prohibited
CREATE OR REPLACE FUNCTION order_prevent_if_domain_operation_prohibited() RETURNS TRIGGER AS $$
DECLARE
    v_lock    RECORD;
BEGIN

    SELECT * INTO v_lock
    FROM v_domain_lock vdl
    WHERE vdl.domain_id = NEW.domain_id
      AND vdl.name = TG_ARGV[0]
      AND (vdl.expiry_date IS NULL OR vdl.expiry_date >= NOW())
    ORDER BY vdl.is_internal DESC -- registrar lock takes precedence
    LIMIT 1;

    IF FOUND THEN
        IF v_lock.is_internal THEN
            RAISE EXCEPTION 'Domain ''%'' % prohibited by registrar', NEW.name, TG_ARGV[0];
        END IF;

        -- check if update lock is being removed as part of this update order
        IF TG_ARGV[0] = 'update' THEN
            IF NEW.locks IS NOT NULL AND NEW.locks ? 'update' AND (NEW.locks->>'update')::boolean IS FALSE THEN
                RETURN NEW;
            END IF;
        END IF;

        RAISE EXCEPTION 'Domain ''%'' % prohibited', NEW.name, TG_ARGV[0];

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_create_domain_contact_does_not_exist
-- description: Simulates a foreign key constraint for the order_contact_id column
-- by ensuring it references an existing ID in either the contact or order_contact table.
CREATE OR REPLACE FUNCTION order_prevent_if_create_domain_contact_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT
            1
        FROM
            contact c
                JOIN v_order_create_domain cd ON cd.order_item_id = NEW.create_domain_id
        WHERE
            c.id = NEW.order_contact_id
          AND c.tenant_customer_id = cd.tenant_customer_id
          AND c.deleted_date IS NULL)
    THEN
        RAISE EXCEPTION 'order_contact_id % does not exist in either contact or order_contact table.', NEW.order_contact_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_update_domain_contact_does_not_exist
-- description: Simulates a foreign key constraint for the order_contact_id column
-- by ensuring it references an existing ID in either the contact or order_contact table.
CREATE OR REPLACE FUNCTION order_prevent_if_update_domain_contact_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT
            1
        FROM
            contact c
                JOIN v_order_update_domain cd ON cd.order_item_id = NEW.update_domain_id
        WHERE
            c.id = NEW.order_contact_id
          AND c.tenant_customer_id = cd.tenant_customer_id
          AND c.deleted_date IS NULL)
    THEN
        RAISE EXCEPTION 'order_contact_id % does not exist in either contact or order_contact table.', NEW.order_contact_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: validate_period()
-- description: Validates the registration or renewal period of a domain
CREATE OR REPLACE FUNCTION validate_period()
    RETURNS TRIGGER AS $$
DECLARE
    allowed_periods INT[];
    period_to_validate INT;
    period_key TEXT;
    validation_type TEXT;
BEGIN
    -- Determine which period to validate based on the trigger argument
    validation_type := TG_ARGV[0];

    IF validation_type = 'registration' THEN
        period_to_validate := NEW.registration_period;
        period_key := 'tld.lifecycle.allowed_registration_periods';
    ELSIF validation_type = 'renewal' THEN
        period_to_validate := NEW.period;
        period_key := 'tld.lifecycle.allowed_renewal_periods';
    ELSIF validation_type = 'transfer_in' THEN
        period_to_validate := NEW.transfer_period;
        period_key := 'tld.lifecycle.allowed_transfer_periods';
    ELSE
        RAISE EXCEPTION 'Invalid validation type: %', validation_type;
    END IF;

    SELECT get_tld_setting(
                   p_key => period_key,
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO allowed_periods;

    -- Check if the period is within the allowed range
    IF NOT (period_to_validate = ANY(allowed_periods)) THEN
        RAISE EXCEPTION '% period must be one of the allowed values: %',
            validation_type, array_to_string(allowed_periods, ', ');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: set_order_contact_id_from_short_id
-- description: Set the order_contact_id based on the short_id of the contact
CREATE OR REPLACE FUNCTION set_order_contact_id_from_short_id() RETURNS TRIGGER AS $$
DECLARE
    _c_id uuid;
BEGIN
    SELECT id INTO _c_id FROM contact WHERE short_id=NEW.short_id AND deleted_date IS NULL;
    NEW.order_contact_id = _c_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'contact does not exists' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_domain_order_type()
-- description: validates if the domain order type is allowed for the TLD
CREATE OR REPLACE FUNCTION validate_domain_order_type() RETURNS TRIGGER AS $$
DECLARE
    v_is_order_allowed  BOOLEAN;
    key                 TEXT;
    order_type          TEXT;
BEGIN
    order_type := TG_ARGV[0];

    IF order_type = 'registration' THEN
        key := 'tld.order.is_registration_allowed';
    ELSIF order_type = 'renew' THEN
        key := 'tld.order.is_renew_allowed';
    ELSIF order_type = 'delete' THEN
        key := 'tld.order.is_delete_allowed';
    ELSIF order_type = 'redeem' THEN
        key := 'tld.order.is_redeem_allowed';
    ELSIF order_type = 'update' THEN
        key := 'tld.order.is_update_allowed';
    ELSIF order_type = 'transfer_in' THEN
        key := 'tld.order.is_transfer_allowed';
    ELSE
        RAISE EXCEPTION 'Invalid order type: %', order_type;
    END IF;

    SELECT get_tld_setting(
        p_key=>key,
        p_accreditation_tld_id=>NEW.accreditation_tld_id
    ) INTO v_is_order_allowed;

    IF NOT v_is_order_allowed THEN
        RAISE EXCEPTION 'TLD ''%'' does not support domain %', tld_part(NEW.name), order_type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_auth_info()
-- description: validates the auth info for a specific order type
CREATE OR REPLACE FUNCTION validate_auth_info() RETURNS TRIGGER AS $$
DECLARE
    order_type                       TEXT;
    v_authcode_mandatory_for_orders  TEXT[];
    v_authcode_supported_for_orders  TEXT[];
    v_authcode_acceptance_criteria   TEXT;
BEGIN
    -- Determine which order type to validate based on the trigger argument
    order_type := TG_ARGV[0];

    -- Get order types that require auth info
    SELECT get_tld_setting(
                   p_key => 'tld.order.authcode_mandatory_for_orders',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO v_authcode_mandatory_for_orders;
    
    -- Get order types that support auth info
    SELECT get_tld_setting(
                   p_key => 'tld.order.authcode_supported_for_orders',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO v_authcode_supported_for_orders;
    
    -- Get the auth info length range
    SELECT get_tld_setting(
                   p_key => 'tld.lifecycle.authcode_acceptance_criteria',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO v_authcode_acceptance_criteria;

    -- Check auth info
    IF NEW.auth_info IS NULL OR NEW.auth_info = '' THEN
        IF order_type = ANY(v_authcode_mandatory_for_orders) THEN
            IF order_type = 'registration' THEN
                NEW.auth_info = generate_random_string();
            ELSE
                RAISE EXCEPTION 'Auth info is mandatory for ''%'' order', order_type;
            END IF;
        END IF;
    ELSIF order_type = ANY(ARRAY_CAT(v_authcode_mandatory_for_orders, v_authcode_supported_for_orders)) THEN
        IF NEW.auth_info !~ v_authcode_acceptance_criteria THEN
            RAISE EXCEPTION 'Auth info does not match the required pattern';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_create_domain_plan()
-- description: validates plan items for domain provisioning
CREATE OR REPLACE FUNCTION validate_create_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain             RECORD;
    v_secdns_record_range       INT4RANGE;
    v_required_contact_types    TEXT[];
    v_order_contact_types       TEXT[];
    _is_premium_domain_enabled  BOOLEAN;
    v_job_data                  JSONB;
    v_claims_period             DATERANGE;
    v_job_id                    UUID;
    v_job_type                  TEXT;
BEGIN
    -- order information
    SELECT
        vocd.*,
        TO_JSONB(a.*) AS accreditation,
        CASE
            WHEN voip.price IS NULL THEN NULL
            ELSE JSONB_BUILD_OBJECT(
                'amount', voip.price,
                'currency', voip.currency_type_code,
                'fraction', voip.currency_type_fraction
            )
        END AS price
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

    -- Get required contact types
    SELECT get_tld_setting(
        p_key => 'tld.contact.required_contact_types',
        p_tld_id=>v_create_domain.tld_id
    ) INTO v_required_contact_types;

    -- Get contact types from the order
    SELECT ARRAY_AGG(DISTINCT tc_name_from_id('domain_contact_type',cdc.domain_contact_type_id))
    INTO v_order_contact_types
    FROM create_domain_contact cdc
    WHERE cdc.create_domain_id = NEW.order_item_id;

    -- Check if the required contact types are present in the order
    IF v_required_contact_types IS NOT NULL AND NOT (array_length(v_required_contact_types, 1) = 1 AND (v_required_contact_types[1] IS NULL OR v_required_contact_types[1] = '')) THEN
        IF NOT (v_order_contact_types @> v_required_contact_types) THEN
            UPDATE create_domain_plan
            SET result_message = FORMAT('One or more required contact types are missing: %s', array_to_string(v_required_contact_types, ', ')),
                validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
            WHERE id = NEW.id;
            
            RETURN NEW;
        END IF;
    END IF;

    -- Check if the domain is a premium domain
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

    v_job_type := 'validate_domain_available';
    IF v_claims_period IS NOT NULL THEN
        IF (v_claims_period @> CURRENT_DATE) THEN
            IF v_create_domain.launch_data IS NOT NULL THEN
                v_job_data = v_job_data || jsonb_build_object('launch_data', v_create_domain.launch_data);
            END IF;
            v_job_type := 'validate_domain_claims';
        END IF;
    END IF;

    v_job_id := job_submit(
        v_create_domain.tenant_customer_id,
        v_job_type,
        NEW.id,
        v_job_data
    );


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_create_domain_host_plan()
-- description: validates plan items for host provisioning
CREATE OR REPLACE FUNCTION validate_create_domain_host_plan() RETURNS TRIGGER AS $$
DECLARE
    v_order_host                RECORD;
    v_create_domain             RECORD;
    v_host_object_supported     BOOLEAN;
    v_job_data                  JSONB;
    v_job_id                    UUID;
BEGIN
    -- Fetch domain creation host details
    SELECT oh.*
    INTO v_order_host
    FROM order_host oh
        JOIN create_domain_nameserver cdn ON cdn.host_id=oh.id
    WHERE
        cdn.id = NEW.reference_id;

    IF NOT FOUND THEN
        -- Update the plan with the captured error message
        UPDATE create_domain_plan
        SET result_message = FORMAT('reference id %s not found in create_domain_nameserver table', NEW.reference_id),
            validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- order information
    SELECT
        vocd.*,
        TO_JSONB(a.*) AS accreditation
    INTO v_create_domain
    FROM v_order_create_domain vocd
    JOIN v_accreditation a ON a.accreditation_id = vocd.accreditation_id
    WHERE vocd.order_item_id = NEW.order_item_id;

    -- Get value of host_object_supported flag
    SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_tld_id=>v_create_domain.tld_id,
        p_tenant_id=>v_create_domain.tenant_id
    )
    INTO v_host_object_supported;

    -- Skip host validation if the host object is not supported for domain accreditation.
    IF v_host_object_supported IS FALSE THEN
        UPDATE create_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed'),
                validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;
        
        RETURN NEW;
    END IF;

    v_job_data := jsonb_build_object(
        'host_name', v_order_host.name,
        'order_item_plan_id', NEW.id,
        'accreditation', v_create_domain.accreditation,
        'tenant_customer_id', v_create_domain.tenant_customer_id,
        'order_metadata', v_create_domain.order_metadata
    );

    v_job_id := job_submit(
        v_create_domain.tenant_customer_id,
        'validate_host_available',
        NEW.id,
        v_job_data
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_update_domain_host_plan()
-- description: validates plan items for host provisioning
CREATE OR REPLACE FUNCTION validate_update_domain_host_plan() RETURNS TRIGGER AS $$
DECLARE
    v_order_host                RECORD;
    v_update_domain             RECORD;
    v_host_object_supported     BOOLEAN;
    v_job_data                  JSONB;
    v_job_id                    UUID;
BEGIN
    -- Fetch domain update host details
    SELECT oh.*
    INTO v_order_host
    FROM order_host oh
        JOIN update_domain_add_nameserver udan ON udan.host_id=oh.id
    WHERE
        udan.id = NEW.reference_id;

    IF NOT FOUND THEN
        -- Update the plan with the captured error message
        UPDATE update_domain_plan
        SET result_message = FORMAT('reference id %s not found in update_domain_add_nameserver table', NEW.reference_id),
            validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- order information
    SELECT
        voud.*,
        TO_JSONB(a.*) AS accreditation
    INTO v_update_domain
    FROM v_order_update_domain voud
    JOIN v_accreditation a ON a.accreditation_id = voud.accreditation_id
    WHERE voud.order_item_id = NEW.order_item_id;

    -- Get value of host_object_supported flag
    SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_tld_id=>v_update_domain.tld_id,
        p_tenant_id=>v_update_domain.tenant_id
    )
    INTO v_host_object_supported;

    -- Skip host validation if the host object is not supported for domain accreditation.
    IF v_host_object_supported IS FALSE THEN
        UPDATE update_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed'),
                validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    v_job_data := jsonb_build_object(
        'host_name', v_order_host.name,
        'order_item_plan_id', NEW.id,
        'accreditation', v_update_domain.accreditation,
        'tenant_customer_id', v_update_domain.tenant_customer_id,
        'order_metadata', v_update_domain.order_metadata
    );

    v_job_id := job_submit(
        v_update_domain.tenant_customer_id,
        'validate_host_available',
        NEW.id,
        v_job_data
    );

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
        CASE
            WHEN voip.price IS NULL THEN NULL
            ELSE JSONB_BUILD_OBJECT(
                'amount', voip.price,
                'currency', voip.currency_type_code,
                'fraction', voip.currency_type_fraction
            )
        END AS price
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
        CASE
            WHEN voip.price IS NULL THEN NULL
            ELSE JSONB_BUILD_OBJECT(
                'amount', voip.price,
                'currency', voip.currency_type_code,
                'fraction', voip.currency_type_fraction
            )
        END AS price
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


-- function: validate_update_domain_plan()
-- description: validates plan items for domain update
CREATE OR REPLACE FUNCTION validate_update_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain         RECORD;
    v_secdns_record_range   INT4RANGE;
BEGIN
    -- order information
    SELECT
        voud.*,
        TO_JSONB(a.*) AS accreditation
    INTO v_update_domain
    FROM v_order_update_domain voud
    JOIN v_accreditation a ON a.accreditation_id = voud.accreditation_id
    WHERE voud.order_item_id = NEW.order_item_id;

    -- Get the range of secdns records for the TLD
    SELECT get_tld_setting(
        p_key => 'tld.dns.secdns_record_count',
        p_accreditation_tld_id => v_update_domain.accreditation_tld_id
    ) INTO v_secdns_record_range;

    -- Validate domain secdns records count
    IF NOT is_update_domain_secdns_count_valid(v_update_domain, v_secdns_record_range) THEN
        UPDATE order_item_plan
        SET result_message = FORMAT('SecDNS record count must be in this range %s-%s', lower(v_secdns_record_range), upper(v_secdns_record_range) - 1),
            validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- Complete validation if not failed
    UPDATE order_item_plan
    SET validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
    WHERE id = NEW.id
    AND validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'started');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: validate_domain_syntax()
-- description: validates the syntax of a domain name
CREATE OR REPLACE FUNCTION validate_domain_syntax() RETURNS TRIGGER AS $$
DECLARE
    v_length_range   INT4RANGE;
    v_name           TEXT;
BEGIN
    SELECT get_tld_setting(
        p_key=>'tld.lifecycle.domain_length',
        p_accreditation_tld_id => NEW.accreditation_tld_id
    )
    INTO v_length_range;

    SELECT domain_name_part(NEW.name) INTO v_name;

    -- Check if the domain name length is within the allowed range
    IF NOT v_length_range @> LENGTH(v_name) THEN
        RAISE EXCEPTION 'Domain name length must be in this range [%-%]', lower(v_length_range), upper(v_length_range)-1;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_tld_active()
-- description: validates if the TLD is active
CREATE OR REPLACE FUNCTION validate_tld_active() RETURNS TRIGGER AS $$
DECLARE
    v_is_tld_active BOOLEAN;
BEGIN
    SELECT get_tld_setting(
        p_key=>'tld.lifecycle.is_tld_active',
        p_accreditation_tld_id=>NEW.accreditation_tld_id
    ) INTO v_is_tld_active;

    IF NOT v_is_tld_active THEN
        RAISE EXCEPTION 'TLD ''%'' is not active', tld_part(NEW.name);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_rem_secdns_exists()
-- description: validate that the secdns record we are trying to remove exists
CREATE OR REPLACE FUNCTION validate_rem_secdns_exists() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.ds_data_id IS NOT NULL THEN
        -- we only need to check ds_data table and not child key_data because
        -- ds_data is generated from key_data
        PERFORM 1 FROM ONLY secdns_ds_data
        WHERE id IN (
            SELECT ds_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND digest = (SELECT digest FROM order_secdns_ds_data WHERE id = NEW.ds_data_id);

        IF NOT FOUND THEN
            RAISE EXCEPTION 'SecDNS DS record to be removed does not exist';
        END IF;

    ELSE
        PERFORM 1 FROM ONLY secdns_key_data
        WHERE id IN (
            SELECT key_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND public_key = (SELECT public_key FROM order_secdns_key_data WHERE id = NEW.key_data_id);

        IF NOT FOUND THEN
            RAISE EXCEPTION 'SecDNS key record to be removed does not exist';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: validate_add_secdns_does_not_exist()
-- description: validate that the secdns record we are trying to add does not exist
CREATE OR REPLACE FUNCTION validate_add_secdns_does_not_exist() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.ds_data_id IS NOT NULL THEN
        -- we only need to check ds_data table and not child key_data because
        -- ds_data is generated from key_data
        PERFORM 1 FROM ONLY secdns_ds_data 
        WHERE id IN (
            SELECT ds_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND digest = (SELECT digest FROM order_secdns_ds_data WHERE id = NEW.ds_data_id);

        IF FOUND THEN
            RAISE EXCEPTION 'SecDNS DS record to be added already exists';
        END IF;

    ELSE
        PERFORM 1 FROM ONLY secdns_key_data
        WHERE id IN (
            SELECT key_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND public_key = (SELECT public_key FROM order_secdns_key_data WHERE id = NEW.key_data_id);

        IF FOUND THEN
            RAISE EXCEPTION 'SecDNS key record to be added already exists';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: order_prevent_if_domain_with_auth_info_does_not_exist()
-- description: check if domain with auth info exists
CREATE OR REPLACE FUNCTION order_prevent_if_domain_with_auth_info_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM domain d
    WHERE d.name = NEW.name
      AND d.auth_info = NEW.auth_info;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Auth info does not match';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: validate_domain_secdns_data()
-- description: validate the domain secdns data
CREATE OR REPLACE FUNCTION validate_domain_secdns_data() RETURNS TRIGGER AS $$
DECLARE
    v_domain                        RECORD;
    v_secdns_supported              TEXT[];
BEGIN
    -- Order information
    IF TG_TABLE_NAME = 'create_domain_secdns' THEN
        SELECT vocd.*, TO_JSONB(a.*) AS accreditation INTO v_domain
        FROM v_order_create_domain vocd
        JOIN v_accreditation a ON a.accreditation_id = vocd.accreditation_id
        WHERE vocd.order_item_id = NEW.create_domain_id;
    ELSE
        SELECT voud.*, TO_JSONB(a.*) AS accreditation INTO v_domain
        FROM v_order_update_domain voud
        JOIN v_accreditation a ON a.accreditation_id = voud.accreditation_id
        WHERE voud.order_item_id = NEW.update_domain_id;
    END IF;

    -- Get the supported secdns records for the TLD
    SELECT get_tld_setting(
        p_key => 'tld.order.secdns_supported',
        p_accreditation_tld_id => v_domain.accreditation_tld_id
    ) INTO v_secdns_supported;

    -- Check if the secdns data is supported for the TLD
    IF v_secdns_supported[1] IS NULL AND (NEW.ds_data_id IS NOT NULL OR NEW.key_data_id IS NOT NULL) THEN
        RAISE EXCEPTION 'SecDNS data is not supported for TLD ''%''', tld_part(v_domain.domain_name);
    ELSE
        IF v_secdns_supported = ARRAY['dsData'] THEN
            IF NEW.ds_data_id IS NULL THEN
                RAISE EXCEPTION 'SecDNS DS data is only supported for TLD ''%''', tld_part(v_domain.domain_name);
            ELSE
                -- Check if the secdns ds has key data
                PERFORM 1 FROM order_secdns_ds_data
                WHERE id = NEW.ds_data_id
                AND key_data_id IS NOT NULL;

                IF FOUND THEN
                    RAISE EXCEPTION 'SecDNS DS data with key data is not supported for TLD ''%''', tld_part(v_domain.domain_name);
                END IF;
            END IF;
        ELSIF v_secdns_supported = ARRAY['keyData'] AND NEW.key_data_id IS NULL THEN
            RAISE EXCEPTION 'SecDNS Key data is only supported for TLD ''%''', tld_part(v_domain.domain_name);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

