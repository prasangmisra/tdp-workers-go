-- function: provision_hosting_create_job TODO: UPDATE
-- description: creates a job to provision a hosting order
CREATE OR REPLACE FUNCTION provision_hosting_create_job() RETURNS TRIGGER AS $$
DECLARE
    v_hosting RECORD;
    v_cuser RECORD;
    v_certificate RECORD;
BEGIN

    IF NEW.certificate_id IS NULL THEN
        SELECT body, private_key, chain INTO v_certificate FROM provision_hosting_certificate_create phc WHERE phc.hosting_id = NEW.hosting_id;
    ELSE
        SELECT body, private_key, chain INTO v_certificate FROM hosting_certificate WHERE id = NEW.certificate_id;
    END IF;


    -- find single customer user (temporary)
    SELECT *
    INTO v_cuser
    FROM v_customer_user vcu
             JOIN v_tenant_customer vtnc ON vcu.customer_id = vtnc.customer_id
    WHERE vtnc.id = NEW.tenant_customer_id
    LIMIT 1;

    WITH components AS (
        SELECT  JSON_AGG(
                        JSONB_BUILD_OBJECT(
                                'name', hc.name,
                                'type', tc_name_from_id('hosting_component_type', hc.type_id)
                        )
                ) AS data
        FROM hosting_component hc
                 JOIN hosting_product_component hpc ON hpc.component_id = hc.id
                 JOIN provision_hosting_create ph ON ph.product_id = hpc.product_id
        WHERE ph.id = NEW.id
    )
    SELECT
        NEW.id as provision_hosting_create_id,
        vtnc.id AS tenant_customer_id,
        ph.domain_name,
        ph.product_id,
        ph.region_id,
        ph.order_metadata AS metadata,
        vtnc.name as customer_name,
        v_cuser.email as customer_email,
        TO_JSONB(hc.*) AS client,
        TO_JSONB(v_certificate.*) AS certificate,
        components.data AS components
    INTO v_hosting
    FROM provision_hosting_create ph
             JOIN components ON TRUE
             JOIN hosting_client hc ON hc.id = ph.client_id
             JOIN v_tenant_customer vtnc ON vtnc.id = ph.tenant_customer_id
    WHERE ph.id = NEW.id;

    UPDATE provision_hosting_create SET job_id = job_submit(
            v_hosting.tenant_customer_id,
            'provision_hosting_create',
            NEW.id,
            to_jsonb(v_hosting.*)
                                                 ) WHERE id = NEW.id;


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_hosting_certificate_create_job
-- description: creates a job to provision a hosting certificate
CREATE OR REPLACE FUNCTION provision_hosting_certificate_create_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id uuid;
    _child_job_id uuid;
    retry_interval interval;
    retry_limit int;
BEGIN
    -- create a certificate job but don't submit it
    SELECT job_create(
                   NEW.tenant_customer_id,
                   'provision_hosting_certificate_create',
                   NEW.id,
                   JSONB_BUILD_OBJECT(
                    'provision_hosting_create_id', NEW.id,
                    'request_id', NEW.hosting_id,
                    'tenant_customer_id', NEW.tenant_customer_id,
                    'domain_name', NEW.domain_name,
                    'order_metadata', NEW.order_metadata
                   )
           ) INTO _parent_job_id;

    UPDATE provision_hosting_certificate_create SET job_id = _parent_job_id WHERE id = NEW.id;

    SELECT vav.value INTO retry_interval 
    FROM v_attr_value vav
    JOIN tenant_customer tc ON  tc.id = NEW.tenant_customer_id
    WHERE vav.category_name = 'hosting' AND vav.tenant_id = tc.tenant_id AND key_name ='dns_check_interval';

    SELECT vav.value INTO retry_limit
    FROM v_attr_value vav
    JOIN tenant_customer tc ON tc.id = NEW.tenant_customer_id
    WHERE vav.category_name = 'hosting' AND vav.tenant_id = tc.tenant_id AND vav. key_name ='dns_check_max_retries';


    SELECT job_submit_retriable(
                   NEW.tenant_customer_id,
                   'provision_hosting_dns_check',
               -- doesn't matter what we set for reference id, this job type will not have a reference table
                   NEW.id,
                   JSONB_BUILD_OBJECT(
                    'domain_name', NEW.domain_name,
                    'order_metadata', NEW.order_metadata
                   ),
                   NOW(),
                   retry_interval,
                   retry_limit,
                   _parent_job_id
           ) INTO _child_job_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_hosting_update_job
-- description: updates a job to update a hosting order
CREATE OR REPLACE FUNCTION provision_hosting_update_job() RETURNS TRIGGER AS $$
DECLARE
    v_hosting RECORD;
BEGIN
    SELECT
        phu.hosting_id as hosting_id,
        vtnc.id AS tenant_customer_id,
        phu.order_metadata AS metadata,
        phu.is_active,
        phu.external_order_id,
        vtnc.name as customer_name,
        TO_JSONB(hcrt.*) AS certificate
    INTO v_hosting
    FROM provision_hosting_update phu
             LEFT OUTER JOIN hosting_certificate hcrt ON hcrt.id = phu.certificate_id
             JOIN v_tenant_customer vtnc ON vtnc.id = phu.tenant_customer_id
    WHERE phu.id = NEW.id;

    UPDATE provision_hosting_update SET job_id = job_submit(
            v_hosting.tenant_customer_id,
            'provision_hosting_update',
            NEW.id,
            to_jsonb(v_hosting.*)
                                                 ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_hosting_delete_job
-- description: deletes a job to provision a hosting order
CREATE OR REPLACE FUNCTION provision_hosting_delete_job() RETURNS TRIGGER AS $$
DECLARE
    v_hosting RECORD;
BEGIN
    SELECT
        NEW.id as provision_hosting_delete_id,
        vtnc.id AS tenant_customer_id,
        phd.order_metadata AS metadata,
        phd.hosting_id,
        phd.external_order_id,
        vtnc.name as customer_name
    INTO v_hosting
    FROM provision_hosting_delete phd
             JOIN v_tenant_customer vtnc ON vtnc.id = phd.tenant_customer_id
    WHERE phd.id = NEW.id;

    UPDATE provision_hosting_delete SET job_id = job_submit(
            v_hosting.tenant_customer_id,
            'provision_hosting_delete',
            NEW.id,
            to_jsonb(v_hosting.*)
                                                 ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
