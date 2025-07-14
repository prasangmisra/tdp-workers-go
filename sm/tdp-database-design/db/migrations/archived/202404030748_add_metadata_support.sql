-- Add metadata column to order table and propagate metadata to jobs

-- changes shown by git diff:

-- plan_create_domain_provision_contact

-- function: plan_create_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain         RECORD;
    _contact_exists         BOOLEAN;
    _contact_provisioned    BOOLEAN;
    _thin_registry          BOOLEAN;
BEGIN
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    SELECT TRUE INTO _contact_exists
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    SELECT value INTO _thin_registry
    FROM v_attribute va
    JOIN v_tenant_customer vtc ON vtc.id = v_create_domain.tenant_customer_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_create_domain.accreditation_tld_id
    WHERE va.key = 'tld.lifecycle.is_thin_registry'
      AND va.tld_id = vat.tld_id
      AND va.tenant_id = vtc.tenant_id;

    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
    AND pc.accreditation_id = v_create_domain.accreditation_id;

    IF FOUND OR _thin_registry THEN
        -- contact has already been provisioned, we can mark this as complete.
        UPDATE create_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;
    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        ) VALUES(
            NEW.reference_id,
            v_create_domain.accreditation_id,
            v_create_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_create_domain.order_metadata
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- plan_create_domain_provision_host

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
      order_item_plan_ids,
      order_metadata
    ) VALUES (
      v_create_domain.accreditation_id,
      v_new_host_id,
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

-- plan_create_hosting_provision

-- function: plan_create_hosting_provision()
-- description: creates provision_hsting_create record to trigger job
CREATE OR REPLACE FUNCTION plan_create_hosting_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_hosting   RECORD;
BEGIN

    SELECT * INTO v_create_hosting
    FROM v_order_create_hosting
    WHERE order_item_id = NEW.order_item_id;

    INSERT INTO provision_hosting_create (
        hosting_id,
        domain_name,
        region_id,
        client_id,
        product_id,
        certificate_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_create_hosting.hosting_id,
        v_create_hosting.domain_name,
        v_create_hosting.region_id,
        v_create_hosting.client_id,
        v_create_hosting.product_id,
        v_create_hosting.certificate_id,
        v_create_hosting.tenant_customer_id,
        v_create_hosting.order_metadata,
        ARRAY[NEW.id]
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- plan_delete_hosting_provision

-- function: plan_delete_hosting_provision()
-- description: creates provision_hsting_delete record to trigger job
CREATE OR REPLACE FUNCTION plan_delete_hosting_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_hosting   RECORD;
BEGIN

    SELECT * INTO v_delete_hosting
    FROM v_order_delete_hosting
    WHERE order_item_id = NEW.order_item_id;

    INSERT INTO provision_hosting_delete (
        hosting_id,
        external_order_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_delete_hosting.hosting_id,
        v_delete_hosting.external_order_id,
        v_delete_hosting.tenant_customer_id,
        v_delete_hosting.order_metadata,
        ARRAY[NEW.id]
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- plan_update_hosting_provision

-- function: plan_update_hosting_provision()
-- description: creates provision_hsting_update record to trigger job
CREATE OR REPLACE FUNCTION plan_update_hosting_provision() RETURNS TRIGGER AS $$
DECLARE
    v_update_hosting   RECORD;
BEGIN

    SELECT * INTO v_update_hosting
    FROM v_order_update_hosting
    WHERE order_item_id = NEW.order_item_id;

    INSERT INTO hosting_certificate (SELECT * FROM hosting_certificate WHERE id=v_update_hosting.certificate_id);

    INSERT INTO provision_hosting_update (
        hosting_id,
        is_active,
        certificate_id,
        external_order_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_update_hosting.hosting_id,
        v_update_hosting.is_active,
        v_update_hosting.certificate_id,
        v_update_hosting.external_order_id,
        v_update_hosting.tenant_customer_id,
        v_update_hosting.order_metadata,
        ARRAY[NEW.id]
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- order_set_metadata

-- function: order_set_metadata()
-- description: Update order metadata by adding order id;
CREATE OR REPLACE FUNCTION order_set_metadata() RETURNS TRIGGER AS $$
BEGIN
    UPDATE "order" SET metadata = metadata || JSONB_BUILD_OBJECT ('order_id', NEW.id);
    RETURN NEW;

END
$$ LANGUAGE plpgsql;

-- recreate trigger since we changed it's function
DROP TRIGGER IF EXISTS order_set_metadata_tg ON "order";
CREATE TRIGGER order_set_metadata_tg 
  AFTER INSERT ON "order" 
  FOR EACH ROW EXECUTE PROCEDURE order_set_metadata();

-- v_order_create_contact

DROP VIEW IF EXISTS v_order_create_contact;
CREATE OR REPLACE VIEW v_order_create_contact AS 
SELECT 
    cc.id AS order_item_id,
    cc.order_id AS order_id,
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
    tc_name_from_id('contact_type',ct.id) AS contact_type,
    cp.first_name,
    cp.last_name,
    cp.org_name
FROM order_item_create_contact cc
    JOIN order_contact oc ON oc.id = cc.contact_id
    JOIN contact_type ct ON ct.id = oc.type_id    
    JOIN order_contact_postal cp ON cp.contact_id = oc.id AND NOT cp.is_international
    JOIN "order" o ON o.id=cc.order_id  
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;

-- v_order_create_hosting

DROP VIEW IF EXISTS v_order_create_hosting;
CREATE OR REPLACE VIEW v_order_create_hosting AS
SELECT
    ch.id AS hosting_id,
    ch.id AS order_item_id,
    ch.order_id AS order_id,
    ch.domain_name,
    ch.region_id,
    ch.product_id,
    chc.id AS client_id,
    chcr.id AS certificate_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.tenant_name,
    tc.name
FROM order_item_create_hosting ch
    JOIN order_item_create_hosting_client chc ON chc.id = ch.client_id
    LEFT OUTER JOIN order_item_create_hosting_certificate chcr ON ch.certificate_id = chcr.id
    JOIN "order" o ON o.id=ch.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id;

-- v_order_delete_hosting

DROP VIEW IF EXISTS v_order_delete_hosting;
CREATE OR REPLACE VIEW v_order_delete_hosting AS
SELECT
    dh.hosting_id AS hosting_id,
    dh.id AS order_item_id,
    dh.order_id AS order_id,
    h.external_order_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.tenant_name,
    tc.name
FROM order_item_delete_hosting dh
    JOIN ONLY hosting h ON h.id = dh.hosting_id
    JOIN "order" o ON o.id=dh.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id;

-- v_order_update_hosting

DROP VIEW IF EXISTS v_order_update_hosting;
CREATE OR REPLACE VIEW v_order_update_hosting AS
SELECT
    uh.hosting_id AS hosting_id,
    uh.id AS order_item_id,
    uh.order_id AS order_id,
    uh.is_active,
    uhcr.id AS certificate_id,
    h.external_order_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.tenant_name,
    tc.name
FROM order_item_update_hosting uh
    JOIN ONLY hosting h ON h.id = uh.hosting_id
    LEFT OUTER JOIN order_item_update_hosting_certificate uhcr ON uh.certificate_id = uhcr.id
    JOIN "order" o ON o.id=uh.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id;

-- v_order_create_host

DROP VIEW IF EXISTS v_order_create_host;
CREATE OR REPLACE VIEW v_order_create_host AS
SELECT
    ch.id AS order_item_id,
    ch.order_id AS order_id,
    oh.name as host_name,
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
    JOIN order_host_addr oha ON oha.host_id = oh.id
    JOIN "order" o ON o.id=ch.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;

-- Add order_metadata column to class.provision table
ALTER TABLE class.provision ADD COLUMN IF NOT EXISTS order_metadata JSONB;

-- provision_contact_job

-- function: provision_contact_job()
-- description: creates the job to create the contact

CREATE OR REPLACE FUNCTION provision_contact_job() RETURNS TRIGGER AS $$
DECLARE
  v_contact     RECORD;
BEGIN

  SELECT 
    NEW.id AS provision_contact_id,
    NEW.tenant_customer_id AS tenant_customer_id,
    jsonb_get_contact_by_id(c.id) AS contact,
    TO_JSONB(a.*) AS accreditation,
    NEW.pw AS pw,
    NEW.order_metadata AS order_metadata
  INTO v_contact
  FROM ONLY contact c 
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
  WHERE c.id=NEW.contact_id;

  UPDATE provision_contact SET job_id=job_submit(
    NEW.tenant_customer_id,
    'provision_contact_create',
    NEW.id,
    TO_JSONB(v_contact.*)
  ) WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- provision_domain_update_job

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
        d.order_metadata,
        d.domain_name AS name,
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
        job_id = job_submit(
        v_domain.tenant_customer_id,
        'provision_domain_update',
        NEW.id,
        TO_JSONB(v_domain.*)
    ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- provision_host_job

-- function: provision_host_job()
-- description: creates the job to create the host
CREATE OR REPLACE FUNCTION provision_host_job() RETURNS TRIGGER AS $$
DECLARE
  v_host     RECORD;
BEGIN

  WITH _host_info  AS (
    SELECT 
      h.id AS host_id,
      name AS host_name,
      ARRAY_AGG(ha.address) FILTER (WHERE FAMILY(ha.address) = 4) AS ipv4_addr,
      ARRAY_AGG(ha.address) FILTER (WHERE FAMILY(ha.address) = 6) AS ipv6_addr
    FROM host h  
      LEFT JOIN host_addr ha ON ha.host_id = h.id
    WHERE h.id = NEW.host_id
    GROUP BY 1,2
  )
  SELECT
    NEW.id AS provision_host_id,
    NEW.tenant_customer_id AS tenant_customer_id,
    TO_JSONB(hi.*) AS host,
    TO_JSONB(a.*) AS accreditation,
    NEW.order_metadata
  INTO v_host
  FROM _host_info hi
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id;


  UPDATE provision_host SET
    job_id=job_submit(
    NEW.tenant_customer_id,
    'provision_host_create',
    NEW.id,
    TO_JSONB(v_host.*)
  ) WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- provision_hosting_create_job

-- function: provision_hosting_create_job TODO: UPDATE
-- description: creates a job to provision a hosting order
CREATE OR REPLACE FUNCTION provision_hosting_create_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
        v_cuser RECORD;
    BEGIN

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
          ph.order_metadata,
          vtnc.name as customer_name,
          v_cuser.email as customer_email,
          TO_JSONB(hc.*) AS client,
          TO_JSONB(hcrt.*) AS certificate,
          components.data AS components
        INTO v_hosting
        FROM provision_hosting_create ph
        JOIN components ON TRUE
        JOIN hosting_client hc ON hc.id = ph.client_id
        LEFT OUTER JOIN hosting_certificate hcrt ON hcrt.id = PH.certificate_id
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

-- provision_hosting_update_job

-- function: provision_hosting_update_job
-- description: updates a job to update a hosting order
CREATE OR REPLACE FUNCTION provision_hosting_update_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
    BEGIN
        SELECT
            phu.hosting_id as hosting_id,
            vtnc.id AS tenant_customer_id,
            phu.order_metadata,
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

-- provision_hosting_delete_job

-- function: provision_hosting_delete_job
-- description: deletes a job to provision a hosting order
CREATE OR REPLACE FUNCTION provision_hosting_delete_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
    BEGIN
        SELECT
            NEW.id as provision_hosting_delete_id,
            vtnc.id AS tenant_customer_id,
            phd.order_metadata,
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
