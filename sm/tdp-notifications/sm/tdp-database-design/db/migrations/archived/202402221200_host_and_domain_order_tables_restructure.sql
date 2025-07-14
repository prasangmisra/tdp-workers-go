--As we don't have product data - this is a data loss migration for a order host creation.
-----------------------------------------------------------------------------------
 DROP TABLE IF EXISTS create_domain_nameserver_addr;
 DROP VIEW IF EXISTS v_order_create_host; 
 DROP TABLE IF EXISTS order_item_create_host_addr;

--------------------------------------------------------------------------------------
--
-- table: order_host
-- description: hosts that are available for this order 
--

CREATE TABLE IF NOT EXISTS order_host(
    CONSTRAINT order_host_pkey PRIMARY KEY (id),
	CONSTRAINT order_host_tenant_customer_id_name_key UNIQUE (tenant_customer_id, name),
	CONSTRAINT order_host_domain_id_fkey FOREIGN KEY (domain_id) REFERENCES public."domain"(id),
	CONSTRAINT order_host_tenant_customer_id_fkey FOREIGN KEY (tenant_customer_id) REFERENCES public.tenant_customer(id)
) INHERITS(host);
-------------------------------------------------------------------------------------
--
-- table: order_host_addr
-- description: addresses that are available for this order_host
--

CREATE TABLE  IF NOT EXISTS order_host_addr(
  FOREIGN KEY (host_id) REFERENCES order_host,
  PRIMARY KEY(id),
  UNIQUE(host_id, address)
) INHERITS(host_addr);

------------------------------------------------------------------------------------ 
 ALTER TABLE create_domain_nameserver
 	DROP COLUMN  IF EXISTS name,
 	ADD COLUMN IF NOT EXISTS host_id  UUID NOT NULL REFERENCES order_host;
 
 CREATE INDEX ON create_domain_nameserver(host_id);


------------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_order_item_plan_object;
ALTER TABLE IF EXISTS  create_host_plan
DROP CONSTRAINT IF EXISTS create_host_plan_order_item_id_fkey;
DROP TABLE IF EXISTS order_item_create_host;

-----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_item_create_host (
  host_id UUID NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (order_id) REFERENCES "order",
  FOREIGN KEY (status_id) REFERENCES order_item_status,
  FOREIGN KEY (host_id) REFERENCES order_host  
) INHERITS (order_item,class.audit_trail);

-- make sure the initial status is 'pending'
CREATE TRIGGER order_item_force_initial_status_tg
  BEFORE INSERT ON order_item_create_host
  FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();
-- creates an execution plan for the item
CREATE TRIGGER a_order_item_create_plan_tg
    AFTER UPDATE ON order_item_create_host
    FOR EACH ROW WHEN ( 
      OLD.status_id <> NEW.status_id 
      AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    )EXECUTE PROCEDURE plan_simple_order_item();
-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_create_host
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();
-- when the order_item completes
CREATE TRIGGER  order_item_finish_tg
  AFTER UPDATE ON order_item_create_host
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 
 
CREATE INDEX ON order_item_create_host(order_id);
CREATE INDEX ON order_item_create_host(status_id);
------------------------------------------------------------------------------------
TRUNCATE TABLE create_host_plan;
ALTER TABLE IF EXISTS  create_host_plan
DROP CONSTRAINT IF EXISTS create_host_plan_order_item_id_fkey,
ADD CONSTRAINT create_host_plan_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES public.order_item_create_host(id);

-----------------------------------------------------------------------------------

--
-- function: create_host_order_from_jsonb()
-- description: Parses a JSONB into the tables order, order_item_create_host, order_host, order_host_addr
--

CREATE OR REPLACE FUNCTION create_host_order_from_jsonb(p_js JSONB) RETURNS UUID AS $$
DECLARE
    _order_id UUID;
    _order_item_create_host_id UUID;
    _order_host_id UUID;
    _addr_js JSONB;  
BEGIN
    -- Store the order attributes and return the order id
    INSERT INTO "order"(
      tenant_customer_id,
      type_id,
      customer_user_id
    )
    VALUES(
      (p_js->>'tenant_customer_id')::UUID,
      (SELECT id FROM v_order_type WHERE name='create' AND product_name='host'),
      (p_js->>'customer_user_id')::UUID
    ) RETURNING id INTO _order_id;

     -- Store to order_host
    INSERT INTO order_host(
      tenant_customer_id,
      "name" 
     )
    VALUES(
     (p_js->>'tenant_customer_id')::UUID,
     p_js->>'name'
    ) RETURNING id INTO _order_host_id;

    -- Store to order_item_create_host
    INSERT INTO order_item_create_host(
      order_id,
      host_id
     )
    VALUES(
      _order_id,  
      _order_host_id
    ) RETURNING id INTO _order_item_create_host_id; 


    -- store host_addr
    FOR _addr_js IN SELECT jsonb_array_elements(p_js->'order_host_addrs')
    LOOP
      INSERT INTO order_host_addr(
        host_id,       
        address
      )
      VALUES(
        _order_host_id,
        (_addr_js->>'address')::INET       
      );
    END LOOP;   

    RETURN _order_id;
END;
$$ LANGUAGE plpgsql;
--------------------------------------------------------------------------------------------------
--
-- function: jsonb_get_create_host_order_by_id()
-- description: returns a jsonb containing all the attributes of a host
--

CREATE OR REPLACE FUNCTION jsonb_get_create_host_order_by_id(p_id UUID) RETURNS JSONB AS $$
DECLARE
  _order_item_create_host_id UUID; 
BEGIN
  SELECT id INTO STRICT _order_item_create_host_id
    FROM order_item_create_host
    WHERE order_id = p_id; 
      RETURN
    (SELECT   jsonb_build_object(    
        'name', oh."name", --  'domain_id', h.domain_id,   
        'order_host_addrs', jsonb_agg(jsonb_build_object('address', oha.address)),
        'tenant_customer_id',o.tenant_customer_id,
        'customer_user_id', o.customer_user_id
    ) AS host_json
    FROM order_item_create_host oich
    JOIN order_host oh ON oh.id=oich.host_id
    JOIN "order" o ON o.id=oich.order_id
    LEFT JOIN order_host_addr oha ON oha.host_id=oich.host_id
    WHERE oich.id = _order_item_create_host_id
    GROUP BY oh.name,o.customer_user_id,o.tenant_customer_id);
END;
$$ LANGUAGE plpgsql STABLE;

--------------------------------------------------------------------------------------------
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
      accreditation_id = v_create_domain.accreditation_id
        AND h.name = v_dc_host.name
        AND ps.name='completed';

  IF NOT FOUND and v_host_object_supported IS TRUE THEN 

    -- upsert the host 
    WITH new_host AS (
      INSERT INTO host(tenant_customer_id,name)
        VALUES(v_create_domain.tenant_customer_id,v_dc_host.name) 
        ON CONFLICT (tenant_customer_id,name) 
        DO UPDATE SET updated_date=NOW()
      RETURNING id
    )
    SELECT id INTO v_new_host_id FROM new_host;

    -- insert the addresses 
    INSERT INTO host_addr(host_id,address) 
      ( 
        SELECT 
          v_new_host_id,
          oha.address 
        FROM order_host_addr oha          
          JOIN create_domain_nameserver cdn  USING (host_id) 
        WHERE 
          cdn.create_domain_id = NEW.order_item_id 
          AND cdn.id = NEW.reference_id
      ) ON CONFLICT DO NOTHING; 

    -- send the host to be provisioned
    -- but if there's a record that's pending
    -- simply add ourselves to those order_item_plan_ids that need
    -- to be updated
    INSERT INTO provision_host(
      accreditation_id,
      host_id,
      tenant_customer_id,
      order_item_plan_ids
    ) VALUES (
      v_create_domain.accreditation_id,
      v_new_host_id,
      v_create_domain.tenant_customer_id,
      ARRAY[NEW.id]
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
----------------------------------------------------------------------------------------------

-- function: plan_create_host_provision()
-- description: create a host based on the plan
CREATE OR REPLACE FUNCTION plan_create_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_host RECORD;
BEGIN
    INSERT INTO host (SELECT h.* FROM host h JOIN order_item_create_host oich ON  h.id = oich.host_id  WHERE oich.id = NEW.reference_id);    
    INSERT INTO host_addr (SELECT ha.* FROM host_addr ha JOIN order_item_create_host oich ON  ha.host_id = oich.host_id WHERE oich.id = NEW.reference_id);

     -- complete the order item
    UPDATE create_host_plan
    SET status_id = tc_id_from_name('order_item_plan_status','completed')
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------


CREATE OR REPLACE VIEW v_order_create_host AS
SELECT
    ch.id AS order_item_id,
    ch.order_id AS order_id,
    oh.name as host_name,
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
    JOIN order_host_addr oha ON oha.host_id = oh.id
    JOIN "order" o ON o.id=ch.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;

  ------------------------------------------------------------------------------------------------ 

--
-- function: jsonb_get_order_by_id()
-- description: returns product_name and jsonb containing all the attributes of order for the product
--

CREATE OR REPLACE FUNCTION jsonb_get_order_by_id(IN p_id UUID, OUT product_name text, OUT order_data JSONB) AS $$
BEGIN
  SELECT vot.product_name INTO product_name
    FROM v_order_type vot 
    JOIN "order" o ON o.type_id = vot.id
    WHERE o.id = p_id;

  IF product_name = 'contact' THEN
    order_data := jsonb_get_create_contact_order_by_id(p_id);
  ELSIF product_name = 'host' THEN
    order_data := jsonb_get_create_host_order_by_id(p_id);
  ELSE
    RAISE EXCEPTION 'unsupported order product name %', product_name;
  END IF;

END;
$$ LANGUAGE plpgsql STABLE;
  ----------------------------------------------------------------------------------
 
 CREATE OR REPLACE VIEW v_order_item_plan_object AS 
SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id, 
  distinct_order_contact.id AS id
FROM order_item_create_domain d 
  JOIN "order" o ON o.id = d.order_id 
  JOIN order_type ot ON ot.id = o.type_id 
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL ( 
    SELECT DISTINCT order_contact_id AS id
    FROM create_domain_contact 
    WHERE create_domain_id = d.id
  ) AS distinct_order_contact ON TRUE
  
  UNION

  SELECT 
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id, 
    distinct_order_host.id AS id
  FROM order_item_create_domain d 
    JOIN "order" o ON o.id = d.order_id 
    JOIN order_type ot ON ot.id = o.type_id 
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj ON obj.name = 'host'
    JOIN LATERAL ( 
      SELECT DISTINCT id AS id
      FROM create_domain_nameserver 
      WHERE create_domain_id = d.id 
    ) AS distinct_order_host ON TRUE

 
  UNION 

  SELECT 
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id, 
    d.id AS id
  FROM order_item_create_domain d 
    JOIN "order" o ON o.id = d.order_id 
    JOIN order_type ot ON ot.id = o.type_id 
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj ON obj.name = 'domain'

  UNION 

  SELECT 
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id, 
    d.id AS id
  FROM order_item_renew_domain d 
    JOIN "order" o ON o.id = d.order_id 
    JOIN order_type ot ON ot.id = o.type_id 
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj ON obj.name = 'domain'

  UNION

  SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id AS object_id,
    d.id AS id
  FROM order_item_redeem_domain d
    JOIN "order" o ON o.id = d.order_id
    JOIN order_type ot ON ot.id = o.type_id
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj on obj.name = 'domain'

  UNION

  SELECT
    d.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    d.id AS id
  FROM order_item_delete_domain d
     JOIN "order" o ON o.id = d.order_id
     JOIN order_type ot ON ot.id = o.type_id
     JOIN product p ON p.id = ot.product_id
     JOIN order_item_object obj ON obj.name = 'domain'

    UNION

    SELECT
        d.id AS order_item_id,
        p.name AS product_name,
        ot.name AS order_type_name,
        obj.name AS object_name,
        obj.id   AS object_id,
        distinct_order_contact.id AS id
    FROM order_item_update_domain d
        JOIN "order" o ON o.id = d.order_id
        JOIN order_type ot ON ot.id = o.type_id
        JOIN product p ON p.id = ot.product_id
        JOIN order_item_object obj ON obj.name = 'contact'
        JOIN LATERAL (
            SELECT DISTINCT order_contact_id AS id
            FROM update_domain_contact
            WHERE update_domain_id = d.id
        ) AS distinct_order_contact ON TRUE

    UNION

    SELECT
        d.id AS order_item_id,
        p.name AS product_name,
        ot.name AS order_type_name,
        obj.name AS object_name,
        obj.id   AS object_id,
        d.id AS id
    FROM order_item_update_domain d
        JOIN "order" o ON o.id = d.order_id
        JOIN order_type ot ON ot.id = o.type_id
        JOIN product p ON p.id = ot.product_id
        JOIN order_item_object obj ON obj.name = 'domain'

  UNION 

  SELECT 
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id, 
    c.id AS id
  FROM order_item_create_contact c 
    JOIN "order" o ON o.id = c.order_id 
    JOIN order_type ot ON ot.id = o.type_id 
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj ON obj.name = 'contact'

  UNION

  SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
  FROM order_item_create_hosting c
    JOIN "order" o ON o.id = c.order_id
    JOIN order_type ot ON ot.id = o.type_id
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj ON obj.name = 'hosting'

  UNION

  SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
  FROM order_item_delete_hosting c
    JOIN "order" o ON o.id = c.order_id
    JOIN order_type ot ON ot.id = o.type_id
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj ON obj.name = 'hosting'

  UNION

  SELECT
    c.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    c.id AS id
  FROM order_item_update_hosting c
    JOIN "order" o ON o.id = c.order_id
    JOIN order_type ot ON ot.id = o.type_id
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj ON obj.name = 'hosting'

  UNION

  SELECT
    h.id AS order_item_id,
    p.name AS product_name,
    ot.name AS order_type_name,
    obj.name AS object_name,
    obj.id   AS object_id,
    h.id AS id
  FROM order_item_create_host h
    JOIN "order" o ON o.id = h.order_id
    JOIN order_type ot ON ot.id = o.type_id
    JOIN product p ON p.id = ot.product_id
    JOIN order_item_object obj ON obj.name = 'host'

;

 
