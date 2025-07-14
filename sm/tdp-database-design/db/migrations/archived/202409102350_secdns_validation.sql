------------------------------------- TABLES -----------------------------------------
UPDATE order_item_strategy
SET is_validation_required = TRUE
WHERE order_type_id = (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update')
AND object_id = tc_id_from_name('order_item_object','domain')
AND provision_order = 2;

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
  'secdns_supported',
  (SELECT id FROM attr_category WHERE name='order'),
  'List of supported secdns types',
  (SELECT id FROM attr_value_type WHERE name='TEXT_LIST'),
  '{}'::TEXT,
  FALSE
),
(
  'secdns_record_count',
  (SELECT id FROM attr_category WHERE name='dns'),
  'Range of minimum and maximum secdns record count',
  (SELECT id FROM attr_value_type WHERE name='INTEGER_RANGE'),
  '[0, 0]'::TEXT,
  FALSE
) ON CONFLICT DO NOTHING;


------------------------------------- FUNCTIONS -------------------------------------

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


-- function: is_create_domain_secdns_count_valid()
-- description: validates the number of secdns records for a domain secdns create order
CREATE OR REPLACE FUNCTION is_create_domain_secdns_count_valid(v_create_domain RECORD, v_secdns_record_range INT4RANGE) RETURNS BOOLEAN AS $$
DECLARE
    v_secdns_record_count   INT;
BEGIN
    -- Get SecDNS records total count
    SELECT COUNT(*)
    INTO v_secdns_record_count
    FROM create_domain_secdns
    WHERE create_domain_id = v_create_domain.order_item_id;

    -- Check if the number of secdns records is within the allowed range
    RETURN v_secdns_record_range @> v_secdns_record_count;
END;
$$ LANGUAGE plpgsql;


-- function: is_update_domain_secdns_count_valid()
-- description: validates the number of secdns records for a domain secdns update order
CREATE OR REPLACE FUNCTION is_update_domain_secdns_count_valid(v_update_domain RECORD, v_secdns_record_range INT4RANGE) RETURNS BOOLEAN AS $$
DECLARE
    v_secdns_record_count   INT;
BEGIN
    -- Get SecDNS records total count
    WITH cur_count AS (
        SELECT
            COUNT(ds.*) AS cnt
        FROM domain_secdns ds
        WHERE ds.domain_id = v_update_domain.domain_id
    ), to_be_added AS (
        SELECT
            COUNT(udas.*) AS cnt
        FROM update_domain_add_secdns udas
        WHERE udas.update_domain_id = v_update_domain.order_item_id
    ), to_be_removed AS (
        SELECT
            COUNT(*) AS cnt
        FROM update_domain_rem_secdns udrs
        WHERE udrs.update_domain_id = v_update_domain.order_item_id
    )
    SELECT
        (SELECT cnt FROM cur_count) +
        (SELECT cnt FROM to_be_added) -
        (SELECT cnt FROM to_be_removed)
    INTO v_secdns_record_count;

    -- Check if the number of secdns records is within the allowed range
    RETURN v_secdns_record_range @> v_secdns_record_count;
END;
$$ LANGUAGE plpgsql;


-- function: validate_create_domain_plan()
-- description: validates plan items for domain provisioning
CREATE OR REPLACE FUNCTION validate_create_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data              JSONB;
    v_create_domain         RECORD;
    v_secdns_record_range   INT4RANGE;
    v_job_id                UUID;
BEGIN
    -- order information
    SELECT
        vocd.*,
        TO_JSONB(a.*) AS accreditation
    INTO v_create_domain
    FROM v_order_create_domain vocd
    JOIN v_accreditation a ON a.accreditation_id = vocd.accreditation_id
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

    v_job_data := jsonb_build_object(
        'domain_name', v_create_domain.domain_name,
        'order_item_plan_id', NEW.id,
        'registration_period', v_create_domain.registration_period,
        'accreditation', v_create_domain.accreditation,
        'tenant_customer_id', v_create_domain.tenant_customer_id,
        'order_metadata', v_create_domain.order_metadata
    );

    v_job_id := job_submit(
        v_create_domain.tenant_customer_id,
        'validate_domain_available',
        NEW.id,
        v_job_data
    );

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


------------------------------------- TRIGGERS -------------------------------------

-- add trigger to validate the domain secdns data
CREATE OR REPLACE TRIGGER validate_domain_secdns_data_tg
  BEFORE INSERT ON create_domain_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_domain_secdns_data();


-- add trigger to validate the domain secdns data
CREATE OR REPLACE TRIGGER validate_domain_secdns_data_tg
  BEFORE INSERT ON update_domain_add_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_domain_secdns_data();


-- validates plan items for domain update
CREATE OR REPLACE TRIGGER validate_update_domain_plan_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
  )
  EXECUTE PROCEDURE validate_update_domain_plan();
