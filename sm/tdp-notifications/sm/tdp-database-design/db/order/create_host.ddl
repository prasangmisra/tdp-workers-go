--
-- table: order_item_create_host
-- description: this table stores attributes of host related orders.
--

CREATE TABLE order_item_create_host (
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

-- prevent create host if already exists 
CREATE TRIGGER order_prevent_if_host_exists_tg
  BEFORE INSERT ON order_item_create_host
  FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_host_exists();  

-- creates an execution plan for the item
CREATE TRIGGER a_order_item_create_plan_tg
  AFTER UPDATE ON order_item_create_host
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE plan_simple_order_item();

-- starts the execution of the order 
CREATE TRIGGER b_order_item_plan_start_tg
  AFTER UPDATE ON order_item_create_host
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
  ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE TRIGGER order_item_finish_tg
  AFTER UPDATE ON order_item_create_host
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
  ) EXECUTE PROCEDURE order_item_finish(); 

CREATE INDEX ON order_item_create_host(order_id);
CREATE INDEX ON order_item_create_host(status_id);

-- this table contains the plan for creating a host
CREATE TABLE create_host_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_create_host
) INHERITS (order_item_plan,class.audit_trail);

-- starts the execution of the create host plan
CREATE TRIGGER plan_create_host_provision_host_tg
  AFTER UPDATE ON create_host_plan
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
  ) EXECUTE PROCEDURE plan_create_host_provision();

CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_host_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

CREATE TRIGGER order_item_plan_processed_tg
  AFTER UPDATE ON create_host_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_processed();



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
