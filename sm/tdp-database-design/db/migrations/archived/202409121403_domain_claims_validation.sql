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
    'validate_domain_claims',
    'Validates domain in claims period ',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobDomainProvision'
)
ON CONFLICT DO NOTHING;


INSERT INTO attr_value_type(name,data_type)
VALUES
    ('DATERANGE','DATERANGE')
ON CONFLICT DO NOTHING;


-- add new tld_setting for claims_period
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
    'claims_period',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Start and end date of claims period',
    (SELECT id FROM attr_value_type WHERE name='DATERANGE'),
    NULL::TEXT,
    FALSE
)
ON CONFLICT DO NOTHING;


ALTER TABLE IF EXISTS attr_value ADD COLUMN IF NOT EXISTS value_daterange DATERANGE;

ALTER TABLE attr_value
    DROP CONSTRAINT attr_value_check1;

ALTER TABLE attr_value
ADD CONSTRAINT attr_value_check1 CHECK(
    (
        (value_integer IS NOT NULL )::INTEGER +
        (value_text IS NOT NULL )::INTEGER +
        (value_integer_range IS NOT NULL )::INTEGER +
        (value_boolean IS NOT NULL )::INTEGER +
        (value_text_list IS NOT NULL )::INTEGER +
        (value_daterange IS NOT NULL )::INTEGER +
        (value_integer_list IS NOT NULL )::INTEGER
    ) = 1
);


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
LEFT JOIN attr_value av ON av.key_id = k.id AND tn.id = av.tenant_id
;


CREATE OR REPLACE VIEW v_attribute AS 

WITH RECURSIVE categories AS (
    SELECT id,name,descr FROM attr_category WHERE parent_id IS NULL
    UNION 
    SELECT c.id,p.name || '.' || c.name,c.descr FROM attr_category c JOIN categories p ON p.id = c.parent_id 
) 

SELECT DISTINCT
    vat.tenant_id,
    vat.tenant_name,
    vat.tld_name AS tld_name,
    vat.tld_id AS tld_id,
    vat.accreditation_tld_id,
    c.name AS path,
    c.id AS category_id,
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
    LEFT JOIN v_attr_value vtld ON vtld.key_id = k.id AND vat.tld_id = vtld.tld_id
    LEFT JOIN v_attr_value vpi ON vpi.key_id = k.id AND vat.provider_instance_id = vpi.provider_instance_id
    LEFT JOIN v_attr_value vp ON vp.key_id = k.id AND vat.provider_id = vp.provider_id
    LEFT JOIN v_attr_value vpr ON vpr.key_id = k.id AND vat.registry_id = vpr.registry_id
ORDER BY tld_name,key;


CREATE TRIGGER v_attribute_update_tg INSTEAD OF UPDATE ON v_attribute 
    FOR EACH ROW EXECUTE PROCEDURE attribute_update();


-- function: validate_create_domain_plan()
-- description: validates plan items for domain provisioning
CREATE OR REPLACE FUNCTION validate_create_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data      JSONB;
    v_create_domain RECORD;
    v_job_id        UUID;
    v_claims_period DATERANGE;
    v_date_now      TIMESTAMP;
BEGIN

    -- order information
    SELECT
        vocd.*,
        TO_JSONB(a.*) AS accreditation
    INTO v_create_domain
    FROM v_order_create_domain vocd
             JOIN v_accreditation a ON a.accreditation_id = vocd.accreditation_id
    WHERE vocd.order_item_id = NEW.order_item_id;

    v_job_data := jsonb_build_object(
            'domain_name', v_create_domain.domain_name,
            'order_item_plan_id', NEW.id,
            'registration_period', v_create_domain.registration_period,
            'accreditation', v_create_domain.accreditation,
            'tenant_customer_id', v_create_domain.tenant_customer_id,
            'order_metadata', v_create_domain.order_metadata,
            'order_item_id', v_create_domain.order_item_id
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