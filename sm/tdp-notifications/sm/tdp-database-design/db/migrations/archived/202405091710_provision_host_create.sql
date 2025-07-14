-- function: get_host_parent_domain()
-- description: gets host parent domain
CREATE OR REPLACE FUNCTION get_host_parent_domain(host RECORD) RETURNS RECORD AS $$
DECLARE
    v_domains TEXT[];
    v_domain  RECORD;
BEGIN
    IF host.domain_id IS NOT NULL THEN
        SELECT * INTO v_domain FROM domain WHERE id=host.domain_id and tenant_customer_id=host.tenant_customer_id;
    ELSE
        v_domains := string_to_array(host.name, '.');
        FOR i IN 2 .. (array_length(v_domains, 1) -1) LOOP
            SELECT * INTO v_domain FROM domain WHERE name=array_to_string(v_domains[i:], '.') and tenant_customer_id=host.tenant_customer_id;
            
            -- check host parent domain
            IF v_domain.id IS NOT NULL THEN
                EXIT;
            END IF;
        END LOOP;
    END IF;

    RETURN v_domain;
END;
$$ LANGUAGE plpgsql;


-- function: check_and_populate_host_parent_domain()
-- description: checks and populates host parent domain
CREATE OR REPLACE FUNCTION check_and_populate_host_parent_domain(host RECORD, order_type TEXT, order_host_id UUID) RETURNS VOID AS $$
DECLARE
    v_parent_domain RECORD;
BEGIN
    -- get host parent domain
    v_parent_domain := get_host_parent_domain(host);

    IF v_parent_domain.id IS NULL THEN
        RAISE EXCEPTION 'Cannot % host ''%''; permission denied', order_type, host.name;
    END IF;

    -- update order host
    UPDATE order_host SET name = host.name, domain_id = v_parent_domain.id WHERE id = order_host_id;
END;
$$ LANGUAGE plpgsql;


-- function: validate_host_parent_domain_customer()
-- description: validates if host and host parent domain belong to same customer
CREATE OR REPLACE FUNCTION validate_host_parent_domain_customer() RETURNS TRIGGER AS $$
DECLARE
    v_host RECORD;
BEGIN
    SELECT * INTO v_host FROM host h WHERE h.id = NEW.host_id;

    IF TG_TABLE_NAME = 'order_item_create_host' THEN
       PERFORM check_and_populate_host_parent_domain(v_host, 'create', NEW.host_id);
    ELSIF TG_TABLE_NAME = 'order_item_update_host' THEN
        PERFORM check_and_populate_host_parent_domain(v_host, 'update', NEW.new_host_id);
    ELSE
        RAISE EXCEPTION 'unsupported order type for host product';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: check_if_tld_supports_host_object()
-- description: checks if tld supports host object or not
CREATE OR REPLACE FUNCTION check_if_tld_supports_host_object(order_type TEXT, order_host_id UUID) RETURNS VOID AS $$
DECLARE
    v_host_object_supported  BOOLEAN;
BEGIN
    SELECT value INTO v_host_object_supported
    FROM v_attribute va
    JOIN order_host oh ON oh.id = order_host_id
    JOIN domain d ON d.id = oh.domain_id
    JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    WHERE va.key = 'tld.order.host_object_supported' AND 
            va.tld_name = vat.tld_name AND 
            va.tenant_id = vtc.tenant_id;

    IF NOT v_host_object_supported THEN
        IF order_type = 'create' THEN
            RAISE EXCEPTION 'Host create not supported';
        ELSE
            RAISE EXCEPTION 'Host update not supported; use domain update on parent domain';
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_host_object_unsupported()
-- description: prevent order completion if tld dosen't support host object
CREATE OR REPLACE FUNCTION order_prevent_if_host_object_unsupported() RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'order_item_create_host' THEN
       PERFORM check_if_tld_supports_host_object('create', NEW.host_id);
    ELSIF TG_TABLE_NAME = 'order_item_update_host' THEN
        PERFORM check_if_tld_supports_host_object('update', NEW.new_host_id);
    ELSE
        RAISE EXCEPTION 'unsupported order type for host product';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;




-- validates if host and host parent domain belong to same customer
DROP TRIGGER IF EXISTS a_validate_host_parent_domain_customer_tg ON order_item_create_host;
CREATE TRIGGER a_validate_host_parent_domain_customer_tg
    BEFORE INSERT ON order_item_create_host 
    FOR EACH ROW EXECUTE PROCEDURE validate_host_parent_domain_customer();


-- prevents order creation if tld does not support host object
DROP TRIGGER IF EXISTS order_prevent_if_host_object_unsupported_tg ON order_item_create_host;
CREATE TRIGGER order_prevent_if_host_object_unsupported_tg
    BEFORE INSERT ON order_item_create_host 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_host_object_unsupported();




-- update host order views
-- v_order_create_host view
DROP VIEW IF EXISTS v_order_create_host;
CREATE OR REPLACE VIEW v_order_create_host AS
SELECT
    ch.id AS order_item_id,
    ch.order_id AS order_id,
    ch.host_id AS host_id,
    oh.name as host_name,
    d.id AS domain_id,
    d.name AS domain_name,
    vat.accreditation_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name,
    oha.address
FROM order_item_create_host ch
    JOIN order_host oh ON oh.id = ch.host_id
    LEFT JOIN order_host_addr oha ON oha.host_id = oh.id
    JOIN domain d ON d.id = oh.domain_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN "order" o ON o.id=ch.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;

-- function: plan_create_host_provision()
-- description: create a host based on the plan
CREATE OR REPLACE FUNCTION plan_create_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_host RECORD;
BEGIN
    -- order information
    SELECT * INTO v_create_host
    FROM v_order_create_host
    WHERE order_item_id = NEW.order_item_id;

    -- insert into provision_host with normal flow
    INSERT INTO provision_host(
        accreditation_id,
        host_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_create_host.accreditation_id,
        v_create_host.host_id,
        v_create_host.tenant_customer_id,
        v_create_host.order_metadata,
        ARRAY[NEW.id]
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



ALTER TABLE IF EXISTS provision_host DROP CONSTRAINT IF EXISTS provision_host_host_id_fkey;
ALTER TABLE IF EXISTS provision_host ADD CONSTRAINT provision_host_host_id_fkey FOREIGN KEY (host_id) REFERENCES public.order_host(id);


-- function: provision_host_job()
-- description: creates the job to create the host
CREATE OR REPLACE FUNCTION provision_host_job() RETURNS TRIGGER AS $$
DECLARE
  v_host     RECORD;
BEGIN
  SELECT
    NEW.id AS provision_host_id,
    NEW.tenant_customer_id AS tenant_customer_id,
    jsonb_get_host_by_id(oh.id) AS host,
    TO_JSONB(va.*) AS accreditation,
    NEW.order_metadata AS order_metadata
  INTO v_host
  FROM order_host oh
  JOIN v_accreditation va ON va.accreditation_id = NEW.accreditation_id
  WHERE oh.id=NEW.host_id;

  UPDATE provision_host SET job_id=job_submit(
    NEW.tenant_customer_id,
    'provision_host_create',
    NEW.id,
    TO_JSONB(v_host.*)
  ) WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_host_success()
-- description: set the host parent domain for provisioned host
CREATE OR REPLACE FUNCTION provision_host_success() RETURNS TRIGGER AS $$
DECLARE
  _host_id UUID;
BEGIN
    -- create new host
    INSERT INTO host (SELECT h.* FROM host h WHERE h.id = NEW.host_id)
      ON CONFLICT (tenant_customer_id,name) DO NOTHING;
               
    INSERT INTO host_addr (SELECT ha.* FROM host_addr ha WHERE ha.host_id = NEW.host_id)
      ON CONFLICT DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- completes the host create order provision
DROP TRIGGER IF EXISTS provision_host_success_tg ON provision_host;
CREATE TRIGGER provision_host_success_tg
  AFTER UPDATE ON provision_host
  FOR EACH ROW WHEN (
      OLD.status_id <> NEW.status_id
      AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_host_success();



-- function: plan_create_domain_provision_host()
-- description: create a host based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_host() RETURNS TRIGGER AS $$
DECLARE
  v_create_domain   RECORD;
  v_dc_host         RECORD;
  v_new_host_id     UUID;
  v_p_host          RECORD;
  v_host_object_supported 	BOOLEAN;
BEGIN
  SELECT cdn.*,oh."name" INTO v_dc_host FROM create_domain_nameserver cdn
  JOIN order_host oh ON oh.id=cdn.host_id
  WHERE cdn.id = NEW.reference_id;

  IF NOT FOUND THEN 
    RAISE EXCEPTION 'reference id % not found in create_domain_nameserver table',
      NEW.reference_id;
  END IF;

  -- load the order information through the v_order_create_domain view
  SELECT * INTO v_create_domain 
    FROM v_order_create_domain 
  WHERE order_item_id = NEW.order_item_id; 
  
  -- get value of host_object_supported	flag
  SELECT va.value INTO v_host_object_supported
    from v_attribute va 
  where va.key = 'tld.order.host_object_supported'
    and va.tld_id = v_create_domain.tld_id ;

  -- check to see if the host is already provisioned in the 
  -- instance 
  SELECT
    ps.name AS status_name,
    ps.is_final AS status_is_final,
    ps.is_success AS status_is_success
  INTO v_p_host FROM provision_host ph 
    JOIN host h ON h.id = ph.host_id
    JOIN provision_status ps ON ps.id = ph.status_id
  WHERE 
      ph.accreditation_id = v_create_domain.accreditation_id
      AND ph.tenant_customer_id = v_create_domain.tenant_customer_id
      AND h.name = v_dc_host.name
      AND ps.name='completed';

  IF NOT FOUND and v_host_object_supported IS TRUE THEN
    -- send the host to be provisioned
    -- but if there's a record that's pending
    -- simply add ourselves to those order_item_plan_ids that need
    -- to be updated
    INSERT INTO provision_host(
      accreditation_id,
      host_id,
      tenant_customer_id,
      order_item_plan_ids,
      order_metadata
    ) VALUES (
      v_create_domain.accreditation_id,
      v_dc_host.host_id,
      v_create_domain.tenant_customer_id,
      ARRAY[NEW.id],
      v_create_domain.order_metadata
    ) ON CONFLICT (host_id,accreditation_id) 
      DO UPDATE 
        SET order_item_plan_ids = provision_host.order_item_plan_ids || EXCLUDED.order_item_plan_ids;
  ELSE 
    -- host has already been provisioned, we can mark this as complete
    -- or host will be provisioned as part of domain (tld does not support host object)
      UPDATE create_domain_plan 
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
      WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- drop ignore_address_if_host_already_exists function
DROP TRIGGER IF EXISTS ignore_address_if_host_already_exists_tg ON order_host_addr;
DROP FUNCTION IF EXISTS ignore_address_if_host_already_exists();

