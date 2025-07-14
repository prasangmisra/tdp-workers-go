INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key,
    is_noop
)
VALUES
(
    'provision_host_update',
    'Updates host in domain specific backend',
    'provision_host_update',
    'provision_status',
    'status_id',
    'WorkerJobHostProvision',  
    FALSE
)
ON CONFLICT DO NOTHING;

-- table: update_host_plan
-- this table contains the plan for updating a host
CREATE TABLE IF NOT EXISTS update_host_plan(
    PRIMARY KEY(id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_update_host
) INHERITS (order_item_plan,class.audit_trail);

-- table: provision_host_update
-- description: This table is for provisioning a domain host update in the backend.
CREATE TABLE IF NOT EXISTS provision_host_update(
    host_id                         UUID NOT NULL REFERENCES host,
    new_host_id                     UUID NOT NULL REFERENCES order_host,
    accreditation_id                UUID NOT NULL REFERENCES accreditation,
    tenant_customer_id              UUID NOT NULL REFERENCES tenant_customer,
    PRIMARY KEY(id)
) INHERITS (class.audit_trail, class.provision);


-- function: jsonb_get_host_by_id()
-- description: returns a jsonb containing all the attributes of a host
CREATE OR REPLACE FUNCTION jsonb_get_host_by_id(p_id UUID) RETURNS JSONB AS $$
BEGIN
    RETURN
    (
        SELECT to_jsonb(h) AS _host_info 
        FROM (
            SELECT 
            h.id AS host_id,
            h.name AS host_name,
            ARRAY_AGG(ha.address) FILTER (WHERE FAMILY(ha.address) = 4) AS ipv4_addr,
            ARRAY_AGG(ha.address) FILTER (WHERE FAMILY(ha.address) = 6) AS ipv6_addr
            FROM host h  
            LEFT JOIN host_addr ha ON ha.host_id = h.id
            WHERE h.id = p_id
            GROUP BY 1,2
        ) h
    );
END;
$$ LANGUAGE plpgsql STABLE;


-- function: provision_host_job()
-- description: creates the job to create the host
CREATE OR REPLACE FUNCTION provision_host_job() RETURNS TRIGGER AS $$
DECLARE
  v_host     RECORD;
BEGIN
  SELECT
    NEW.id AS provision_host_id,
    NEW.tenant_customer_id AS tenant_customer_id,
    jsonb_get_host_by_id(h.id) AS host,
    TO_JSONB(va.*) AS accreditation,
    NEW.order_metadata AS order_metadata
  INTO v_host
  FROM ONLY host h 
  JOIN v_accreditation va ON va.accreditation_id = NEW.accreditation_id
  WHERE h.id=NEW.host_id;

  UPDATE provision_host SET job_id=job_submit(
    NEW.tenant_customer_id,
    'provision_host_create',
    NEW.id,
    TO_JSONB(v_host.*)
  ) WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: get_host_addrs()
-- description: returns a array containing all addresses an host
CREATE OR REPLACE FUNCTION get_host_addrs(p_id UUID) RETURNS INET[] AS $$
DECLARE
    host_addrs INET[];
BEGIN
    SELECT ARRAY(SELECT unnest(ARRAY_AGG(DISTINCT ha.address)) ORDER BY 1) INTO host_addrs
    FROM only host h
    LEFT JOIN only host_addr ha ON ha.host_id = h.id
    WHERE h.id = p_id;
   
    RETURN host_addrs;
END;
$$ LANGUAGE plpgsql STABLE;


-- function: get_order_host_addrs()
-- description: returns a array containing all addresses an order host
CREATE OR REPLACE FUNCTION get_order_host_addrs(p_id UUID) RETURNS INET[] AS $$
DECLARE
    order_host_addrs INET[];
BEGIN
    SELECT ARRAY(SELECT unnest(ARRAY_AGG(DISTINCT oha.address)) ORDER BY 1) INTO order_host_addrs
    FROM order_host oh
    LEFT JOIN order_host_addr oha ON oha.host_id = oh.id
    WHERE oh.id = p_id;
   
    RETURN order_host_addrs;
END;
$$ LANGUAGE plpgsql STABLE;


-- function: plan_update_host_provision()
-- description: update a host based on the plan
CREATE OR REPLACE FUNCTION plan_update_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_update_host       RECORD;
BEGIN
    -- order information
    SELECT * INTO v_update_host
    FROM v_order_update_host
    WHERE order_item_id = NEW.order_item_id;

    -- check addresses
    IF NOT get_host_addrs(v_update_host.host_id) = get_order_host_addrs(v_update_host.new_host_id) THEN
        -- insert into provision_host_update with normal flow
       INSERT INTO provision_host_update(
            tenant_customer_id,
            host_id,
            new_host_id,
            accreditation_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES (
            v_update_host.tenant_customer_id,
            v_update_host.host_id,
            v_update_host.new_host_id,
            v_update_host.accreditation_id,
            v_update_host.order_metadata,
            ARRAY [NEW.id]
        );
    ELSE
        -- complete the order item
        UPDATE update_host_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_host_update_job()
-- description: creates host update parent and child jobs
CREATE OR REPLACE FUNCTION provision_host_update_job() RETURNS TRIGGER AS $$
DECLARE
    v_host     RECORD;
BEGIN
  SELECT
    NEW.id AS provision_host_update_id,
    NEW.tenant_customer_id AS tenant_customer_id,
    oh.id AS host_id,
    oh.name AS host_name,
    get_order_host_addrs(oh.id) AS host_new_addrs,
    get_host_addrs(NEW.host_id) AS host_old_addrs,
    TO_JSONB(va.*) AS accreditation,
    NEW.order_metadata AS order_metadata
  INTO v_host
  FROM ONLY order_host oh
  JOIN v_accreditation va ON va.accreditation_id = NEW.accreditation_id
  WHERE oh.id=NEW.new_host_id;

  UPDATE provision_host_update SET job_id=job_submit(
    v_host.tenant_customer_id,
    'provision_host_update',
    NEW.id,
    to_jsonb(v_host.*)
  ) WHERE id=NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_host_update_success()
-- description: updates the host once the provision job completes
CREATE OR REPLACE FUNCTION provision_host_update_success() RETURNS TRIGGER AS $$
DECLARE
  new_host_addrs INET[];
  old_host_addrs INET[];
BEGIN
    -- get host addrs
    new_host_addrs := get_order_host_addrs(NEW.new_host_id);
    old_host_addrs := get_host_addrs(NEW.host_id);

    -- add new addrs
    FOR i IN 1 .. array_length(new_host_addrs, 1) LOOP
      IF NOT new_host_addrs[i] = ANY(old_host_addrs) THEN
        INSERT INTO host_addr (host_id, address) VALUES (NEW.host_id, new_host_addrs[i]);
      END IF;
    END LOOP;

    -- remove old addrs
    FOR j IN 1 .. array_length(old_host_addrs, 1) LOOP
      IF NOT old_host_addrs[j] = ANY(new_host_addrs) THEN
        DELETE FROM host_addr WHERE host_id = NEW.host_id AND address = old_host_addrs[j];
      END IF;
    END LOOP;

    -- set host parent domain
    UPDATE host h 
    SET domain_id = oh.domain_id 
    FROM order_host oh 
    WHERE h.id = NEW.host_id AND oh.id = NEW.new_host_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- starts the execution of the update host plan
DROP TRIGGER IF EXISTS plan_update_host_provision_host_tg ON update_host_plan;
CREATE TRIGGER plan_update_host_provision_host_tg
  AFTER UPDATE ON update_host_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
  ) EXECUTE PROCEDURE plan_update_host_provision();

-- completes the update host plan 
DROP TRIGGER IF EXISTS order_item_plan_update_tg ON update_host_plan;
CREATE TRIGGER order_item_plan_update_tg
  AFTER UPDATE ON update_host_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  ) EXECUTE PROCEDURE order_item_plan_update();

-- starts the host update order provision 
DROP TRIGGER IF EXISTS provision_host_update_job_tg ON provision_host_update;
CREATE TRIGGER provision_host_update_job_tg
  AFTER INSERT ON provision_host_update
  FOR EACH ROW EXECUTE PROCEDURE provision_host_update_job();

-- completes the host update order provision 
DROP TRIGGER IF EXISTS provision_host_update_success_tg ON provision_host_update;
CREATE TRIGGER provision_host_update_success_tg
  AFTER UPDATE ON provision_host_update
  FOR EACH ROW WHEN (
      OLD.status_id <> NEW.status_id
      AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_host_update_success();
