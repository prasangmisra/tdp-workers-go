ALTER TABLE
    order_item_create_domain
ADD
    COLUMN auth_info TEXT;

-- update view
CREATE
OR REPLACE VIEW v_order_create_domain AS
SELECT
    cd.id AS order_item_id,
    cd.order_id AS order_id,
    cd.accreditation_tld_id,
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
    at.provider_name,
    at.provider_instance_id,
    at.provider_instance_name,
    at.tld_id AS tld_id,
    at.tld_name AS tld_name,
    at.accreditation_id,
    cd.name AS domain_name,
    cd.registration_period AS registration_period,
    cd.auto_renew,
    cd.locks,
    cd.auth_info
FROM
    order_item_create_domain cd
    JOIN "order" o ON o.id = cd.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = cd.accreditation_tld_id;

-- update provision function 
-- function: plan_create_domain_provision_domain()
-- description: create a domain based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
  v_create_domain   RECORD;
  v_pd_id           UUID;
  v_parent_id       UUID;
  v_locks_required_changes jsonb;
  v_order_item_plan_ids UUID[];
BEGIN

    -- order information
  SELECT * INTO v_create_domain 
    FROM v_order_create_domain 
  WHERE order_item_id = NEW.order_item_id;

    WITH pd_ins AS (
        INSERT INTO provision_domain(
             domain_name,
             registration_period,
             accreditation_id,
             accreditation_tld_id,
             tenant_customer_id,
             auto_renew,
             pw,
             order_metadata
            ) VALUES(
            v_create_domain.domain_name,
            v_create_domain.registration_period,
            v_create_domain.accreditation_id,
            v_create_domain.accreditation_tld_id,
            v_create_domain.tenant_customer_id,
            v_create_domain.auto_renew,
            COALESCE(v_create_domain.auth_info, TC_GEN_PASSWORD(16)),
            v_create_domain.order_metadata
            ) RETURNING id
    )
    SELECT id INTO v_pd_id FROM pd_ins;

  SELECT
     jsonb_object_agg(key, value)
  INTO v_locks_required_changes FROM jsonb_each(v_create_domain.locks) WHERE value::BOOLEAN = TRUE;

   IF NOT is_jsonb_empty_or_null(v_locks_required_changes) THEN
       WITH inserted_domain_update AS (
           INSERT INTO provision_domain_update(
               domain_name,
               accreditation_id,
               accreditation_tld_id,
               tenant_customer_id,
               order_metadata,
               order_item_plan_ids,
               locks
               )
               VALUES (
              v_create_domain.domain_name,
              v_create_domain.accreditation_id,
              v_create_domain.accreditation_tld_id,
              v_create_domain.tenant_customer_id,
              v_create_domain.order_metadata,
              ARRAY[NEW.id],
              v_locks_required_changes
              )
               RETURNING id
       )

       SELECT id INTO v_parent_id FROM inserted_domain_update;
   ELSE
       v_order_item_plan_ids := ARRAY [NEW.id];
   end if;

  -- we now signal the provisioning 


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

  UPDATE provision_domain SET is_complete = TRUE,
    order_item_plan_ids = v_order_item_plan_ids,
    parent_id = v_parent_id
    WHERE id = v_pd_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;