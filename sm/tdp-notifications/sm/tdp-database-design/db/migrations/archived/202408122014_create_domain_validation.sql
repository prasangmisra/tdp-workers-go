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
    'validate_domain_available',
    'Validates domain available in the backend',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobDomainProvision'
),
(
    'validate_host_available',
    'Validates host available in the backend',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobHostProvision'
)
ON CONFLICT DO NOTHING;


CREATE OR REPLACE FUNCTION validate_create_domain_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data      JSONB;
    v_create_domain RECORD;
    v_job_id        UUID;
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


CREATE OR REPLACE FUNCTION validate_create_domain_host_plan() RETURNS TRIGGER AS $$
DECLARE
    v_job_data                  JSONB;
    v_dc_host                   RECORD;
    v_create_domain             RECORD;
    v_host_object_supported     BOOLEAN;
    v_host_accreditation        RECORD;
    v_job_id                    UUID;
BEGIN

    -- Fetch domain creation host details
    SELECT cdn.*, oh."name", oh.tenant_customer_id, oh.domain_id
    INTO v_dc_host
    FROM create_domain_nameserver cdn
    JOIN order_host oh ON oh.id=cdn.host_id
    WHERE cdn.id = NEW.reference_id;

    IF v_dc_host.id IS NULL THEN
        -- Update the plan with the captured error message
        UPDATE create_domain_plan
        SET result_message = FORMAT('reference id % not found in create_domain_nameserver table', NEW.reference_id),
            validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
        WHERE id = NEW.id;
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
        p_tld_id=>v_create_domain.tld_id
    )
    INTO v_host_object_supported;

    -- Host provisioning will be skipped if the host object is not supported for domain accreditation.
    IF v_host_object_supported IS FALSE THEN
        UPDATE create_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed'),
                validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;
        
        RETURN NEW;
    END IF;

    v_job_data := jsonb_build_object(
        'host_name', v_dc_host.name,
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

-- function: plan_create_domain_provision_host()
-- description: create a host based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_host() RETURNS TRIGGER AS $$
DECLARE
    v_dc_host                                   RECORD;
    v_create_domain                             RECORD;
    v_host_object_supported                     BOOLEAN;
    v_host_parent_domain                        RECORD;
    v_host_accreditation                        RECORD;
    v_host_addrs                                INET[];
    v_host_addrs_empty                          BOOLEAN;
BEGIN
    -- Fetch domain creation host details
    SELECT cdn.*,oh."name",oh.tenant_customer_id,oh.domain_id
    INTO v_dc_host
    FROM create_domain_nameserver cdn
             JOIN order_host oh ON oh.id=cdn.host_id
    WHERE
        cdn.id = NEW.reference_id;

    IF v_dc_host.id IS NULL THEN
        RAISE EXCEPTION 'reference id % not found in create_domain_nameserver table', NEW.reference_id;
    END IF;

    -- Load the order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    -- Get value of host_object_supported	flag
    SELECT get_tld_setting(
                   p_key=>'tld.order.host_object_supported',
                   p_tld_id=>v_create_domain.tld_id
           )
    INTO v_host_object_supported;

    -- Host provisioning will be skipped
    -- if the host object is not supported for domain accreditation
    IF v_host_object_supported IS FALSE THEN
        UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
        RETURN NEW;
    END IF;

    -- Host Accreditation
    v_host_accreditation := get_accreditation_tld_by_name(v_dc_host.name, v_dc_host.tenant_customer_id);

    IF v_host_accreditation IS NOT NULL THEN
        IF v_create_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
            -- Host and domain are under same accreditation, run additional checks 

            v_host_parent_domain := get_host_parent_domain(v_dc_host);

            IF v_host_parent_domain.id IS NULL THEN
                -- customer does not own parent domain
                RAISE EXCEPTION 'Host create not allowed';
            END IF;
            
            -- Check if there are addrs or not
            v_host_addrs := get_order_host_addrs(v_dc_host.host_id);
            v_host_addrs_empty := array_length(v_host_addrs, 1) = 1 AND v_host_addrs[1] IS NULL;
            
            IF v_host_addrs_empty THEN
                -- ip addresses are required to provision host under parent tld
                RAISE EXCEPTION 'Missing IP addresses for hostname';
            END IF;
        END IF;
    END IF;

    INSERT INTO provision_host(
        accreditation_id,
        host_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_create_domain.accreditation_id,
        v_dc_host.host_id,
        v_create_domain.tenant_customer_id,
        v_create_domain.order_metadata,
        ARRAY[NEW.id]
    ) ON CONFLICT (host_id,accreditation_id)
    DO UPDATE
    SET order_item_plan_ids = provision_host.order_item_plan_ids || EXCLUDED.order_item_plan_ids;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            error_message TEXT;
        BEGIN
            -- Capture the error message
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;

            -- Update the plan with the captured error message
            UPDATE create_domain_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION provision_domain_host_skipped() RETURNS TRIGGER AS $$
DECLARE
    v_dc_host   RECORD;
BEGIN
    -- Fetch domain creation host details
    SELECT cdn.*
    INTO v_dc_host
    FROM create_domain_nameserver cdn
    WHERE
        cdn.id = NEW.reference_id;

    -- create new host
    INSERT INTO host (SELECT h.* FROM host h WHERE h.id = v_dc_host.host_id)
    ON CONFLICT (tenant_customer_id,name) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS validate_create_domain_plan_tg ON create_domain_plan;
CREATE TRIGGER validate_create_domain_plan_tg
    AFTER INSERT ON create_domain_plan
    FOR EACH ROW WHEN (
      NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
    )
    EXECUTE PROCEDURE validate_create_domain_plan();

DROP TRIGGER IF EXISTS validate_create_domain_host_plan_tg ON create_domain_plan;
CREATE TRIGGER validate_create_domain_host_plan_tg
    AFTER INSERT ON create_domain_plan
    FOR EACH ROW WHEN (
      NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','pending')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host')
    )
    EXECUTE PROCEDURE validate_create_domain_host_plan();

DROP TRIGGER IF EXISTS plan_create_domain_provision_host_skipped_tg ON create_domain_plan;
CREATE TRIGGER plan_create_domain_provision_host_skipped_tg 
  AFTER UPDATE ON create_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id = tc_id_from_name('order_item_plan_status','new')
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','completed')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host') 
  )
  EXECUTE PROCEDURE provision_domain_host_skipped();


CREATE OR REPLACE FUNCTION provision_domain_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
BEGIN
    WITH contacts AS (
        SELECT JSONB_AGG(
                       JSONB_BUILD_OBJECT(
                               'type',ct.name,
                               'handle',pc.handle
                       )
               ) AS data
        FROM provision_domain pd
                 JOIN provision_domain_contact pdc
                      ON pdc.provision_domain_id=pd.id
                 JOIN domain_contact_type ct ON ct.id=pdc.contact_type_id
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
                 JOIN provision_status ps ON ps.id = pc.status_id
        WHERE
            ps.is_success AND ps.is_final
          AND pd.id = NEW.id
    ),
         hosts AS (
             SELECT JSONB_AGG(data) AS data
             FROM
                 (SELECT JSONB_BUILD_OBJECT(
                                 'name',
                                 h.name,
                                 'ip_addresses',
                                 COALESCE(jsonb_agg(ha.address) FILTER (WHERE ha.host_id IS NOT NULL), '[]')
                         ) as data
                  FROM provision_domain pd
                           JOIN provision_domain_host pdh ON pdh.provision_domain_id=pd.id
                           JOIN ONLY host h ON h.id = pdh.host_id
                           -- addresses might be omitted if customer is not authoritative
                           -- or host already existed at registry
                           LEFT JOIN ONLY host_addr ha on ha.host_id = h.id 
                  WHERE pd.id=NEW.id
                  GROUP BY h.name) sub_q
         ),
         price AS (
             SELECT
                 JSONB_BUILD_OBJECT(
                         'amount', voip.price,
                         'currency', voip.currency_code,
                         'fraction', voip.currency_fraction
                 ) AS data
             FROM v_order_item_price voip
                      JOIN v_order_create_domain vocd ON voip.order_item_id = vocd.order_item_id AND voip.order_id = vocd.order_id
             WHERE vocd.domain_name = NEW.domain_name
             ORDER BY vocd.created_date DESC
             LIMIT 1
         )
    SELECT
        NEW.id AS provision_contact_id,
        tnc.id AS tenant_customer_id,
        d.domain_name AS name,
        d.registration_period,
        d.pw AS pw,
        contacts.data AS contacts,
        hosts.data AS nameservers,
        price.data AS price,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS metadata
    INTO v_domain
    FROM provision_domain d
             JOIN contacts ON TRUE
             JOIN hosts ON TRUE
             LEFT JOIN price ON TRUE
             JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
             JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE d.id = NEW.id;

    UPDATE provision_domain SET job_id = job_submit(
                v_domain.tenant_customer_id,
                'provision_domain_create',
                NEW.id,
                TO_JSONB(v_domain.*)
                 ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION provision_host;
DROP FUNCTION is_host_provisioned;

\i triggers.ddl
\i provisioning/triggers.ddl
