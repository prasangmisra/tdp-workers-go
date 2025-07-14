 -- ticket TDP-2726

CREATE OR REPLACE FUNCTION plan_create_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
  v_domain          RECORD;
  v_create_domain   RECORD;
  v_pd_id           UUID;
BEGIN

    -- order information
  SELECT * INTO v_create_domain 
    FROM v_order_create_domain 
  WHERE order_item_id = NEW.order_item_id; 

  -- we now signal the provisioning 
  WITH pd_ins AS ( 
    INSERT INTO provision_domain(
      name,
      registration_period,
      accreditation_id,
      accreditation_tld_id,
      tenant_customer_id,
      auto_renew,
      order_item_plan_ids
    ) VALUES(
      v_create_domain.domain_name,
      v_create_domain.registration_period,
      v_create_domain.accreditation_id,
      v_create_domain.accreditation_tld_id,
      v_create_domain.tenant_customer_id,
      v_create_domain.auto_renew,
      ARRAY[NEW.id]
    ) RETURNING id
  )
  SELECT id INTO v_pd_id FROM pd_ins;

  -- insert contacts
  INSERT INTO provision_domain_contact(
    provision_domain_id,
    contact_id,
    contact_type_id
  )
  ( SELECT 
      v_pd_id, 
      order_contact_id,
      domain_contact_type_id
    FROM create_domain_contact
    WHERE create_domain_id = NEW.order_item_id
  );

  -- insert hosts
  INSERT INTO provision_domain_host(
    provision_domain_id,
    host_id
  ) (
    SELECT
      v_pd_id,
      h.id
    FROM ONLY host h
    JOIN order_host oh ON oh.name = h.name
    JOIN create_domain_nameserver cdn ON cdn.host_id = oh.id
    WHERE cdn.create_domain_id = NEW.order_item_id AND oh.tenant_customer_id = h.tenant_customer_id 
  );

  UPDATE provision_domain SET is_complete = TRUE WHERE id = v_pd_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


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