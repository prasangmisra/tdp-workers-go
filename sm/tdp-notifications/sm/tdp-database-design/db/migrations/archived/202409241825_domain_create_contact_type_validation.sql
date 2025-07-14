------------------------------------- TABLES -----------------------------------------
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
    'optional_contact_types',
    (SELECT id FROM attr_category WHERE name='contact'),
    'Optional contact types by registry',
    (SELECT id FROM attr_value_type WHERE name='TEXT_LIST'),
    '{}'::TEXT,
    TRUE
) ON CONFLICT DO NOTHING;


------------------------------------- FUNCTIONS -------------------------------------

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
    v_date_now                  TIMESTAMP;
    v_job_id                    UUID;
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


-- function: is_contact_type_supported_for_tld()
-- description: validates the domain contact type
CREATE OR REPLACE FUNCTION is_contact_type_supported_for_tld(contact_type_id UUID, accreditation_tld_id UUID) RETURNS BOOLEAN AS $$
DECLARE
    v_required_contact_types TEXT[];
    v_optional_contact_types TEXT[];
    v_contact_type           TEXT;
BEGIN
    -- Get contact type name
    SELECT tc_name_from_id('domain_contact_type', contact_type_id) INTO v_contact_type;

    -- Get required and optional contact types for the TLD
    SELECT
        get_tld_setting(p_key => 'tld.contact.required_contact_types', p_accreditation_tld_id => accreditation_tld_id) AS v_required_contact_types,
        get_tld_setting(p_key => 'tld.contact.optional_contact_types', p_accreditation_tld_id => accreditation_tld_id) AS v_optional_contact_types
    INTO 
        v_required_contact_types, 
        v_optional_contact_types;

    -- Check if the contact type is valid
    RETURN v_contact_type = ANY(ARRAY_CAT(v_required_contact_types, v_optional_contact_types));
END;
$$ LANGUAGE plpgsql;


-- function: plan_create_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain             RECORD;
    _contact_exists             BOOLEAN;
    _domain_contact_type_id     UUID;
    _thin_registry              BOOLEAN;
    _contact_provisioned        BOOLEAN;
BEGIN
    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    SELECT TRUE INTO _contact_exists
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    -- Get contact type from the order
    SELECT domain_contact_type_id INTO _domain_contact_type_id
    FROM create_domain_contact
    WHERE order_contact_id = NEW.reference_id 
        AND create_domain_id = NEW.order_item_id;

    -- Check if the registry is thin
    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.is_thin_registry', 
        p_tld_id => v_create_domain.tld_id, 
        p_tenant_id => v_create_domain.tenant_id
    ) INTO _thin_registry;

    -- Check if contact is already provisioned 
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_create_domain.accreditation_id;

    IF FOUND OR _thin_registry OR NOT is_contact_type_supported_for_tld(_domain_contact_type_id, v_create_domain.accreditation_tld_id) THEN
        -- Skip contact provision if contact is already provisioned or if the registry is thin or if the contact type is not allowed
        UPDATE create_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;
    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        ) VALUES(
            NEW.reference_id,
            v_create_domain.accreditation_id,
            v_create_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_create_domain.order_metadata
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


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
        AND is_contact_type_supported_for_tld(domain_contact_type_id, v_create_domain.accreditation_tld_id)
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
