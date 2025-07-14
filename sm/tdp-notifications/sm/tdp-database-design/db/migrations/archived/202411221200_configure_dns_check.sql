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

INSERT INTO attr_category(name,descr)
VALUES ('hosting', 'Hosting general settings')
ON CONFLICT DO NOTHING;

INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES
(
  'dns_check_interval',
  (select id FROM attr_category WHERE name='hosting'),
  'Interval in units for checking DNS setup',
  (SELECT id FROM attr_value_type WHERE name='INTERVAL'),
  '1 hour'::TEXT,
  FALSE
),
(
  'dns_check_max_retries',
  (select id FROM attr_category WHERE name='hosting'),
  'Maximum number of retries for checking DNS setup',
  (SELECT id FROM attr_value_type WHERE name='INTERVAL'),
  '72'::INT,
  FALSE
)
ON CONFLICT DO NOTHING;