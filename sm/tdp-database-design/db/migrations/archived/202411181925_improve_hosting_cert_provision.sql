-- function: provision_hosting_certificate_create_job
-- description: creates a job to provision a hosting certificate
CREATE OR REPLACE FUNCTION provision_hosting_certificate_create_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id uuid;
    _child_job_id uuid;
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
                   INTERVAL '4 hours',
                   18,
                   _parent_job_id
           ) INTO _child_job_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
