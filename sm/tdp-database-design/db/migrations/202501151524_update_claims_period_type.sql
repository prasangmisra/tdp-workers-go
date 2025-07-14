-- Add TSTZRANGE type to attr_value_type table
INSERT INTO attr_value_type(name, data_type)
VALUES
    ('TSTZRANGE', 'TSTZRANGE')
ON CONFLICT DO NOTHING;

-- Update value_type_id in attr_key for name claims_period
UPDATE attr_key
SET value_type_id = (SELECT id FROM attr_value_type WHERE name='TSTZRANGE')
WHERE name = 'claims_period';

-- Add value_tstzrange column to attr_value table
ALTER TABLE IF EXISTS attr_value ADD COLUMN IF NOT EXISTS value_tstzrange TSTZRANGE;

-- Update attr_value_check1 constraint to include value_tstzrange
ALTER TABLE attr_value
    DROP CONSTRAINT IF EXISTS attr_value_check1;

ALTER TABLE attr_value
ADD CONSTRAINT attr_value_check1 CHECK(
    (
        (value_integer IS NOT NULL)::INTEGER +
        (value_text IS NOT NULL)::INTEGER +
        (value_integer_range IS NOT NULL)::INTEGER +
        (value_boolean IS NOT NULL)::INTEGER +
        (value_text_list IS NOT NULL)::INTEGER +
        (value_daterange IS NOT NULL)::INTEGER +
        (value_integer_list IS NOT NULL)::INTEGER +
        (value_tstzrange IS NOT NULL)::INTEGER
    ) = 1
);

-- Drop and recreate v_attr_value view to include value_tstzrange
DROP VIEW IF EXISTS v_attr_value CASCADE;
CREATE OR REPLACE VIEW v_attr_value AS
SELECT
    tn.id AS tenant_id,
    tn.name AS tenant_name,
    k.category_id,
    ag.name AS category_name,
    k.id AS key_id,
    k.name AS key_name,
    vt.name AS data_type_name,
    vt.data_type,
    COALESCE(
        av.value_integer::TEXT,
        av.value_text::TEXT,
        av.value_integer_range::TEXT,
        av.value_boolean::TEXT,
        av.value_text_list::TEXT,
        av.value_integer_list::TEXT,
        av.value_daterange::TEXT,
        av.value_tstzrange::TEXT,
        k.default_value::TEXT
    ) AS value,
    av.id IS NULL AS is_default,
    av.tld_id,
    av.provider_instance_id,
    av.provider_id,
    av.registry_id
FROM attr_key k
JOIN tenant tn ON TRUE
JOIN attr_category ag ON ag.id = k.category_id
JOIN attr_value_type vt ON vt.id = k.value_type_id
LEFT JOIN attr_value av ON av.key_id = k.id AND tn.id = av.tenant_id;

DROP VIEW IF EXISTS v_attribute CASCADE;
CREATE OR REPLACE VIEW v_attribute AS 

WITH RECURSIVE categories AS (
    SELECT id, name, descr, name AS parent_attr_category FROM attr_category WHERE parent_id IS NULL
    UNION 
    SELECT c.id, p.name || '.' || c.name, c.descr, p.name AS parent_attr_category FROM attr_category c JOIN categories p ON p.id = c.parent_id 
) 

SELECT DISTINCT
    vat.tenant_id,
    vat.tenant_name,
    vat.tld_name AS tld_name,
    vat.tld_id AS tld_id,
    vat.accreditation_tld_id,
    c.name AS path,
    c.id AS category_id,
    c.parent_attr_category,
    k.id AS key_id,
    avt.data_type,
    avt.name AS data_type_name,
    c.name || '.' || k.name AS key,
    COALESCE(vtld.value,vpi.value,vp.value,vpr.value,v.value,k.default_value) AS value,
    COALESCE(vtld.is_default,vpi.is_default,vp.is_default,vpr.is_default,v.is_default,TRUE) AS is_default
FROM v_accreditation_tld vat 
    JOIN categories c ON TRUE
    JOIN attr_key k ON k.category_id = c.id 
    JOIN attr_value_type avt ON avt.id = k.value_type_id
    LEFT JOIN v_attr_value v 
        ON  v.tenant_id = vat.tenant_id
        AND v.key_id = k.id
        AND COALESCE(v.tld_id,v.provider_instance_id,v.provider_id,v.registry_id) IS NULL
    LEFT JOIN v_attr_value vtld ON vtld.key_id = k.id AND vat.tld_id = vtld.tld_id AND vat.tenant_id = vtld.tenant_id
    LEFT JOIN v_attr_value vpi ON vpi.key_id = k.id AND vat.provider_instance_id = vpi.provider_instance_id
    LEFT JOIN v_attr_value vp ON vp.key_id = k.id AND vat.provider_id = vp.provider_id
    LEFT JOIN v_attr_value vpr ON vpr.key_id = k.id AND vat.registry_id = vpr.registry_id
ORDER BY tld_name,key;


CREATE TRIGGER v_attribute_update_tg INSTEAD OF UPDATE ON v_attribute 
    FOR EACH ROW EXECUTE PROCEDURE attribute_update();

-- Update validate_create_domain_plan function to handle tstzrange
CREATE OR REPLACE FUNCTION validate_create_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain             RECORD;
    v_secdns_record_range       INT4RANGE;
    v_required_contact_types    TEXT[];
    v_order_contact_types       TEXT[];
    _is_premium_domain_enabled  BOOLEAN;
    v_job_data                  JSONB;
    v_claims_period             TSTZRANGE;
    v_date_now                  TIMESTAMPTZ;
    v_job_id                    UUID;
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