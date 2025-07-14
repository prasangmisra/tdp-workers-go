CREATE OR REPLACE FUNCTION validate_create_domain_plan() RETURNS TRIGGER AS
$$
DECLARE
    v_create_domain            RECORD;
    v_secdns_record_range      INT4RANGE;
    v_required_contact_types   TEXT[];
    v_order_contact_types      TEXT[];
    _is_premium_domain_enabled BOOLEAN;
    v_job_data                 JSONB;
    v_claims_period            DATERANGE;
    v_job_id                   UUID;
    v_job_type                 TEXT;
BEGIN
    -- order information
    SELECT vocd.*,
           TO_JSONB(a.*) AS accreditation,
           CASE
               WHEN voip.price IS NULL THEN NULL
               ELSE JSONB_BUILD_OBJECT(
                       'amount', voip.price,
                       'currency', voip.currency_type_code,
                       'fraction', voip.currency_type_fraction
                    )
               END       AS price
    INTO v_create_domain
    FROM v_order_create_domain vocd
             JOIN v_accreditation a ON a.accreditation_id = vocd.accreditation_id
             LEFT JOIN v_order_item_price voip ON voip.order_item_id = vocd.order_item_id
    WHERE vocd.order_item_id = NEW.order_item_id;

    -- Get the range of secdns records for the TLD
    SELECT get_tld_setting(
                   p_key => 'tld.dns.secdns_record_count',
                   p_accreditation_tld_id => v_create_domain.accreditation_tld_id
           )
    INTO v_secdns_record_range;

    -- Validate domain secdns records count
    IF NOT is_create_domain_secdns_count_valid(v_create_domain, v_secdns_record_range) THEN
        UPDATE order_item_plan
        SET result_message       = FORMAT('SecDNS record count must be in this range %s-%s',
                                          lower(v_secdns_record_range), upper(v_secdns_record_range) - 1),
            validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- Get required contact types
    SELECT get_tld_setting(
                   p_key => 'tld.contact.required_contact_types',
                   p_tld_id=>v_create_domain.tld_id
           )
    INTO v_required_contact_types;

    -- Get contact types from the order
    SELECT ARRAY_AGG(DISTINCT tc_name_from_id('domain_contact_type', cdc.domain_contact_type_id))
    INTO v_order_contact_types
    FROM create_domain_contact cdc
    WHERE cdc.create_domain_id = NEW.order_item_id;

    -- Check if the required contact types are present in the order
    IF v_required_contact_types IS NOT NULL AND NOT (array_length(v_required_contact_types, 1) = 1 AND
                                                     (v_required_contact_types[1] IS NULL OR
                                                      v_required_contact_types[1] = '')) THEN
        IF NOT (v_order_contact_types @> v_required_contact_types) THEN
            UPDATE create_domain_plan
            SET result_message       = FORMAT('One or more required contact types are missing: %s',
                                              array_to_string(v_required_contact_types, ', ')),
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
           )
    INTO _is_premium_domain_enabled;

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
           )
    INTO v_claims_period;

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