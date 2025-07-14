-- Adding metadata column to order, provision_domain, provision_domain_renew, provision_domain_redeem, provision_domain_delete, provision_domain_update tables 
-- to propagate order details

ALTER TABLE "order" 
ADD COLUMN IF NOT EXISTS metadata JSONB;

ALTER TABLE provision_domain 
ADD COLUMN IF NOT EXISTS order_metadata JSONB;

ALTER TABLE provision_domain_renew 
ADD COLUMN IF NOT EXISTS order_metadata JSONB;

ALTER TABLE provision_domain_redeem 
ADD COLUMN IF NOT EXISTS order_metadata JSONB;

ALTER TABLE provision_domain_delete 
ADD COLUMN IF NOT EXISTS order_metadata JSONB;

ALTER TABLE provision_domain_update 
ADD COLUMN IF NOT EXISTS order_metadata JSONB;


-- Adding is_cond column to job_status and provision_status tables to add new statuses
ALTER TABLE job_status
ADD COLUMN IF NOT EXISTS is_cond BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE provision_status
ADD COLUMN IF NOT EXISTS is_cond BOOLEAN NOT NULL DEFAULT FALSE;


-- drop job_status_is_final_is_success_idx
DROP INDEX IF EXISTS job_status_is_final_is_success_idx;
CREATE UNIQUE INDEX ON job_status(is_final,is_success,is_cond) WHERE is_final;


-- Insert new job status
INSERT INTO job_status(name,descr,is_final,is_success,is_cond) 
VALUES ('completed_conditionally','Job has completed conditionally',true,true,true) 
ON CONFLICT DO NOTHING;

-- Insert new provision status
INSERT INTO provision_status(name,descr,is_success,is_final,is_cond)
VALUES ('pending_action','pending an event',false,false,true)
ON CONFLICT DO NOTHING;


-- updates the referenced table with the referenced status values
-- ensuring that this matches the job result.  
CREATE OR REPLACE FUNCTION job_reference_status_update() RETURNS TRIGGER AS $$
DECLARE
_job_type         RECORD;
_job_status       RECORD;
_target_status    RECORD;
BEGIN

   SELECT * INTO _job_type FROM job_type WHERE id = NEW.type_id;

   IF _job_type.reference_table IS NULL THEN 
      RETURN NEW;
   END IF;

   SELECT * INTO _job_status FROM job_status WHERE id = NEW.status_id;

   IF NOT _job_status.is_final THEN 
      RETURN NEW;
   END IF;

  IF _job_status.is_cond THEN
   EXECUTE FORMAT('SELECT * FROM %s WHERE is_final = false AND is_cond',_job_type.reference_status_table)
      INTO _target_status;
  ELSE
   EXECUTE FORMAT('SELECT * FROM %s WHERE is_final AND is_cond = false AND is_success = $1',_job_type.reference_status_table)
      INTO _target_status
      USING _job_status.is_success;
  END IF;

   IF NOT FOUND THEN 
      RAISE EXCEPTION 'no target status found in table % where is_success=%',
         _job_type.reference_status_table,_job_status.is_success;
   END IF;


   EXECUTE FORMAT('UPDATE "%s" SET %s = $1 WHERE id = $2',
      _job_type.reference_table,
      _job_type.reference_status_column
   )
   USING _target_status.id,NEW.reference_id;
   
   RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- function: order_set_metadata()
-- description: Update order metadata by adding order id
CREATE OR REPLACE FUNCTION order_set_metadata() RETURNS TRIGGER AS $$
BEGIN
    UPDATE "order" SET metadata=JSONB_BUILD_OBJECT ('order_id', NEW.id);
    RETURN NEW;
END
$$ LANGUAGE plpgsql;



DROP TRIGGER IF EXISTS order_set_metadata_tg ON "order";
CREATE TRIGGER order_set_metadata_tg 
  AFTER INSERT ON "order" 
  FOR EACH ROW EXECUTE PROCEDURE order_set_metadata();


DROP VIEW IF EXISTS v_order_create_domain;
CREATE OR REPLACE VIEW v_order_create_domain AS 
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
    cd.auto_renew
FROM order_item_create_domain cd 
    JOIN "order" o ON o.id=cd.order_id  
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = cd.accreditation_tld_id    
;


DROP VIEW IF EXISTS v_order_redeem_domain;
CREATE OR REPLACE VIEW v_order_redeem_domain AS
SELECT
    rd.id AS order_item_id,
    rd.order_id AS order_id,
    rd.accreditation_tld_id,
    d.name AS domain_name,
    d.id   AS domain_id,
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
    at.accreditation_id
FROM order_item_redeem_domain rd
    JOIN "order" o ON o.id=rd.order_id  
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = rd.accreditation_tld_id
    JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=rd.name
;


DROP VIEW IF EXISTS v_order_renew_domain;
CREATE OR REPLACE VIEW v_order_renew_domain AS 
SELECT 
    rd.id AS order_item_id,
    rd.order_id AS order_id,
    rd.accreditation_tld_id,
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
    d.name AS domain_name,
    d.id   AS domain_id,
    rd.period AS period,
    rd.current_expiry_date
FROM order_item_renew_domain rd
    JOIN "order" o ON o.id=rd.order_id  
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = rd.accreditation_tld_id    
    JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=rd.name -- domain from the same tenant_customer
;


DROP VIEW IF EXISTS v_order_delete_domain;
CREATE OR REPLACE VIEW v_order_delete_domain AS
SELECT
    dd.id AS order_item_id,
    dd.order_id AS order_id,
    dd.accreditation_tld_id,
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
    d.name AS domain_name,
    d.id   AS domain_id
FROM order_item_delete_domain dd
     JOIN "order" o ON o.id=dd.order_id
     JOIN v_order_type ot ON ot.id = o.type_id
     JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
     JOIN order_status s ON s.id = o.status_id
     JOIN v_accreditation_tld at ON at.accreditation_tld_id = dd.accreditation_tld_id
     JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=dd.name
;


DROP VIEW IF EXISTS v_order_update_domain;
CREATE OR REPLACE VIEW v_order_update_domain AS
SELECT
    ud.id AS order_item_id,
    ud.order_id AS order_id,
    ud.accreditation_tld_id,
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
    d.name AS domain_name,
    d.id AS domain_id,
    ud.auth_info,
    ud.hosts,
    ud.auto_renew
FROM order_item_update_domain ud
     JOIN "order" o ON o.id=ud.order_id
     JOIN v_order_type ot ON ot.id = o.type_id
     JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
     JOIN order_status s ON s.id = o.status_id
     JOIN v_accreditation_tld at ON at.accreditation_tld_id = ud.accreditation_tld_id
     JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=ud.name
;



-- function: plan_create_domain_provision_domain()
-- description: create a domain based on the plan
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
      order_item_plan_ids,
      order_metadata
    ) VALUES(
      v_create_domain.domain_name,
      v_create_domain.registration_period,
      v_create_domain.accreditation_id,
      v_create_domain.accreditation_tld_id,
      v_create_domain.tenant_customer_id,
      v_create_domain.auto_renew,
      ARRAY[NEW.id],
      v_create_domain.order_metadata
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
    WHERE cdn.create_domain_id = NEW.order_item_id
  );

  UPDATE provision_domain SET is_complete = TRUE WHERE id = v_pd_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_delete_domain_provision()
-- description: deletes a domain based on the plan
CREATE OR REPLACE FUNCTION plan_delete_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_domain RECORD;
BEGIN
    SELECT * INTO v_delete_domain
    FROM v_order_delete_domain
    WHERE order_item_id = NEW.order_item_id;

    INSERT INTO provision_domain_delete(
        domain_id,
        accreditation_id,
        tenant_customer_id,
        order_item_plan_ids,
        order_metadata
    ) VALUES(
        v_delete_domain.domain_id,
        v_delete_domain.accreditation_id,
        v_delete_domain.tenant_customer_id,
        ARRAY[NEW.id],
        v_delete_domain.order_metadata
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_renew_domain_provision()
-- description: renews a domain based on the plan
CREATE OR REPLACE FUNCTION plan_renew_domain_provision() RETURNS TRIGGER AS $$
DECLARE
  v_domain          RECORD;
  v_renew_domain   RECORD;
  v_pd_id           UUID;
BEGIN

    -- order information
  SELECT * INTO v_renew_domain 
    FROM v_order_renew_domain 
  WHERE order_item_id = NEW.order_item_id; 

  -- -- we now signal the provisioning 
  INSERT INTO provision_domain_renew(
    domain_id,
    period,
    accreditation_id,
    tenant_customer_id,
    current_expiry_date,
    order_item_plan_ids,
    order_metadata
  ) VALUES(
    v_renew_domain.domain_id,
    v_renew_domain.period,
    v_renew_domain.accreditation_id,
    v_renew_domain.tenant_customer_id,
    v_renew_domain.current_expiry_date,
    ARRAY[NEW.id],
    v_renew_domain.order_metadata
  );


  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_redeem_domain_provision()
-- description: redeem a domain based on the plan
CREATE OR REPLACE FUNCTION plan_redeem_domain_provision() RETURNS TRIGGER AS $$
DECLARE
  v_domain RECORD;
  v_redeem_domain RECORD;
BEGIN

    -- order info
    SELECT * INTO v_redeem_domain
    FROM v_order_redeem_domain
    WHERE order_item_id = NEW.order_item_id;

    -- insert into provision table to trigger job creation
    INSERT INTO provision_domain_redeem(
    domain_name,
    domain_id,
    tenant_customer_id,
    accreditation_id,
    order_item_plan_ids,
    order_metadata
    ) VALUES(
    v_redeem_domain.domain_name,
    v_redeem_domain.domain_id,
    v_redeem_domain.tenant_customer_id,
    v_redeem_domain.accreditation_id,
    ARRAY[NEW.id],
    v_redeem_domain.order_metadata
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_domain_provision_domain()
-- description: update a domain based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_pd_id                     UUID;
BEGIN

    -- order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- we now signal the provisioning
    WITH pd_ins AS (
        INSERT INTO provision_domain_update(
            name,
            auth_info,
            hosts,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            auto_renew,
            order_item_plan_ids,
            order_metadata
        ) VALUES(
            v_update_domain.domain_name,
            v_update_domain.auth_info,
            v_update_domain.hosts,
            v_update_domain.accreditation_id,
            v_update_domain.accreditation_tld_id,
            v_update_domain.tenant_customer_id,
            v_update_domain.auto_renew,
            ARRAY[NEW.id],
            v_update_domain.order_metadata
        ) RETURNING id
    )
    SELECT id INTO v_pd_id FROM pd_ins;

    -- insert contacts
    INSERT INTO provision_domain_update_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )
    (
        SELECT
            v_pd_id,
            order_contact_id,
            domain_contact_type_id
        FROM update_domain_contact
        WHERE update_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain_update SET is_complete = TRUE WHERE id = v_pd_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- function: provision_domain_job()
-- description: creates the job to create the domain
CREATE OR REPLACE FUNCTION provision_domain_job() RETURNS TRIGGER AS $$
DECLARE
  v_domain     RECORD;
  hr           RECORD;
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
        SELECT jsonb_agg(data) as data
        FROM
            (SELECT json_build_object(
                'name',
                h.name,
                'ip_addresses',
                jsonb_agg(ha.address)
            ) as data
            FROM provision_domain pd
              JOIN provision_domain_host pdh ON pdh.provision_domain_id=pd.id
              JOIN host h ON h.id = pdh.host_id
              JOIN provision_host ph ON ph.host_id = h.id
              JOIN provision_status ps ON ps.id = ph.status_id
              join host_addr ha on h.id = ha.host_id
            WHERE
              ps.is_success AND ps.is_final
              AND pdh.provision_domain_id=NEW.id
            GROUP BY h.name) sub_q
  )
  SELECT 
    NEW.id AS provision_contact_id,
    tnc.id AS tenant_customer_id,
    d.name AS name,
    d.registration_period,
    d.pw AS pw,
    contacts.data AS contacts,
    hosts.data AS nameservers,
    TO_JSONB(a.*) AS accreditation,
    TO_JSONB(vat.*) AS accreditation_tld,
    d.order_metadata AS order_metadata
  INTO v_domain 
  FROM provision_domain d 
    JOIN contacts ON TRUE 
    JOIN hosts ON TRUE
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
  WHERE d.id = NEW.id;
  
  UPDATE provision_domain SET 
    job_id = job_create(
    v_domain.tenant_customer_id,
    'provision_domain_create',
    NEW.id,
    TO_JSONB(v_domain.*)
  ) WHERE id=NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_renew_job()
-- description: creates the job to renew the domain
CREATE OR REPLACE FUNCTION provision_domain_renew_job() RETURNS TRIGGER AS $$
DECLARE
  v_renew     RECORD;
BEGIN

  SELECT 
    NEW.id AS provision_domain_renew_id,
    tnc.id AS tenant_customer_id,
    TO_JSONB(a.*) AS accreditation,
    d.name AS domain_name,
    d.ry_expiry_date AS expiry_date,
    pr.period  AS period,
    pr.order_metadata AS order_metadata
  INTO v_renew
  FROM provision_domain_renew pr 
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    JOIN domain d ON d.id=pr.domain_id
  WHERE pr.id = NEW.id;

  UPDATE provision_domain_renew SET job_id=job_create(
    v_renew.tenant_customer_id,
    'provision_domain_renew',
    NEW.id,
    TO_JSONB(v_renew.*)
  ) WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_redeem_job()
-- description: creates the job to redeem the domain
CREATE OR REPLACE FUNCTION provision_domain_redeem_job() RETURNS TRIGGER AS $$
DECLARE
  v_redeem RECORD;
BEGIN
    WITH contacts AS (
        SELECT JSON_AGG(
                    JSONB_BUILD_OBJECT(
                            'type', dct.name,
                            'handle',dc.handle
                    )
            ) AS data
        FROM provision_domain_redeem pdr
        JOIN domain d ON d.id = pdr.domain_id
        JOIN domain_contact dc on dc.domain_id = d.id
        JOIN domain_contact_type dct ON dct.id = dc.domain_contact_type_id
        WHERE pdr.id = NEW.id
    ),
        hosts AS (
            SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                                'name',
                                h.name
                        )
                ) AS data
            FROM provision_domain_redeem pdr
            JOIN domain d ON d.id = pdr.domain_id
            JOIN domain_host dh ON dh.domain_id = d.id
            JOIN host h ON h.id = dh.host_id
            WHERE pdr.id = NEW.id
        )
    SELECT
    d.name AS domain_name,
    'ok' AS status,
    d.deleted_date AS delete_date,
    NOW() AS restore_date,
    d.ry_expiry_date AS expiry_date,
    d.ry_created_date AS create_date,
    contacts.data AS contacts,
    hosts.data AS nameservers,
    TO_JSONB(a.*) AS accreditation,
    tnc.id AS tenant_customer_id,
    NEW.id AS provision_domain_redeem_id,
    pr.order_metadata AS order_metadata
    INTO v_redeem
    FROM provision_domain_redeem pr
    JOIN contacts ON TRUE
    JOIN hosts ON TRUE
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    JOIN domain d ON d.name=pr.domain_name
    WHERE pr.id = NEW.id;

    UPDATE provision_domain_redeem SET job_id=job_create(
    v_redeem.tenant_customer_id,
    'provision_domain_redeem',
    NEW.id,
    TO_JSONB(v_redeem.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_delete_job()
-- description: creates the job to delete the domain
CREATE OR REPLACE FUNCTION provision_domain_delete_job() RETURNS TRIGGER AS $$
DECLARE
  v_delete     RECORD;
BEGIN

  SELECT 
    NEW.id AS provision_domain_delete_id,
    tnc.id AS tenant_customer_id,
    TO_JSONB(a.*) AS accreditation,
    d.name AS domain_name,
    pd.order_metadata AS order_metadata
  INTO v_delete
  FROM provision_domain_delete pd 
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    JOIN domain d ON d.id=pd.domain_id
  WHERE pd.id = NEW.id;

  UPDATE provision_domain_delete SET job_id=job_create(
    v_delete.tenant_customer_id,
    'provision_domain_delete',
    NEW.id,
    TO_JSONB(v_delete.*)
  ) WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_update_job()
-- description: creates the job to update the domain.
CREATE OR REPLACE FUNCTION provision_domain_update_job() RETURNS TRIGGER AS $$
DECLARE
  v_domain     RECORD;
BEGIN
    WITH contacts AS(
        SELECT JSONB_AGG(
                       JSONB_BUILD_OBJECT(
                               'type', ct.name,
                               'handle', pc.handle
                       )
               ) AS data
        FROM provision_domain_update_contact pdc
        JOIN domain_contact_type ct ON ct.id =  pdc.contact_type_id
        JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        JOIN provision_status ps ON ps.id = pc.status_id
        WHERE
            ps.is_success AND ps.is_final
            AND pdc.provision_domain_update_id = NEW.id
    ), hosts AS(
        SELECT JSONB_AGG(data) AS data
        FROM(
            SELECT
                JSON_BUILD_OBJECT(
                        'name', h.name,
                        'ip_addresses', JSONB_AGG(ha.address)
                ) AS data
            FROM host h
            JOIN host_addr ha ON h.id = ha.host_id
            WHERE h.name IN (SELECT UNNEST(NEW.hosts))
            GROUP BY h.name
        ) sub_q
    )
    SELECT
        NEW.id AS provision_domain_update_id,
        tnc.id AS tenant_customer_id,
        d.name AS name,
        d.auth_info AS pw,
        contacts.data AS contacts,
        hosts.data as nameservers,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS order_metadata
    INTO v_domain
    FROM provision_domain_update d
    LEFT JOIN contacts ON TRUE
    LEFT JOIN hosts ON TRUE
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE d.id = NEW.id;

    UPDATE provision_domain_update SET
        job_id = job_create(
        v_domain.tenant_customer_id,
        'provision_domain_update',
        NEW.id,
        TO_JSONB(v_domain.*)
    ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- function: build_order_notification_payload()
-- description: grab all plan and order data for given order id
CREATE OR REPLACE FUNCTION build_order_notification_payload(_order_id UUID) RETURNS JSONB AS $$
DECLARE
  _payload      JSONB;
BEGIN
    WITH order_items AS (
        SELECT JSON_AGG(
                       JSONB_BUILD_OBJECT(
                               'object', object_name,
                               'status', plan_status_name,
                               'error', result_message
                       )
               ) AS data
        FROM v_order_item_plan
        WHERE order_id = _order_id
    )
    SELECT
        JSONB_BUILD_OBJECT(
                'order_id', o.order_id,
                'order_status_name', o.order_status_name,
                'order_item_plans', order_items.data
        )
    INTO _payload
    FROM v_order o
    JOIN order_items ON TRUE
    WHERE order_id = _order_id;

    RETURN _payload;
END;
$$ LANGUAGE plpgsql;



-- function: notify_order_status_transition_final_tgf()
-- description: Notify about an order status transitioning to a final state to a channel specific to a given order id
CREATE OR REPLACE FUNCTION notify_order_status_transition_final_tfg() RETURNS TRIGGER AS $$
DECLARE
  _payload      JSONB;
BEGIN
    _payload = build_order_notification_payload(OLD.id);
    PERFORM notify_event('order_notify','order_event_notify',_payload::TEXT);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: notify_order_status()
-- description: Notify about an order status
CREATE OR REPLACE FUNCTION notify_order_status(_order_id UUID) RETURNS BOOLEAN AS $$
DECLARE
  _payload      JSONB;
BEGIN
    _payload = build_order_notification_payload(_order_id);
    PERFORM notify_event('order_notify','order_event_notify',_payload::TEXT);
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- function: provision_order_status_notify()
-- description: Notify about an provision order status
CREATE OR REPLACE FUNCTION provision_order_status_notify() RETURNS TRIGGER AS $$
DECLARE
  _order_id      UUID;
BEGIN
    _order_id = (NEW.order_metadata->>'order_id')::UUID;
    PERFORM notify_order_status(_order_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS provision_domain_order_notify_on_pending_action_tgf ON provision_domain;
CREATE TRIGGER provision_domain_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();


DROP TRIGGER IF EXISTS provision_domain_renew_order_notify_on_pending_action_tgf ON provision_domain_renew;
CREATE TRIGGER provision_domain_renew_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain_renew
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();


DROP TRIGGER IF EXISTS provision_domain_redeem_order_notify_on_pending_action_tgf ON provision_domain_redeem;
CREATE TRIGGER provision_domain_redeem_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain_redeem
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();


DROP TRIGGER IF EXISTS provision_domain_delete_order_notify_on_pending_action_tgf ON provision_domain_delete;
CREATE TRIGGER provision_domain_delete_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain_delete
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();


DROP TRIGGER IF EXISTS provision_domain_update_order_notify_on_pending_action_tgf ON provision_domain_update;
CREATE TRIGGER provision_domain_update_order_notify_on_pending_action_tgf
  AFTER UPDATE ON provision_domain_update
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND NEW.status_id = tc_id_from_name('provision_status','pending_action')
  ) EXECUTE PROCEDURE provision_order_status_notify();
