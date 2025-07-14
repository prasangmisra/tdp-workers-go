ALTER TABLE provision_domain ADD COLUMN IF NOT EXISTS ry_cltrid TEXT;

ALTER TABLE provision_domain_renew ADD COLUMN IF NOT EXISTS ry_cltrid TEXT;
ALTER TABLE provision_domain_renew ADD COLUMN IF NOT EXISTS domain_name FQDN NOT NULL;

ALTER TABLE provision_domain_redeem ADD COLUMN IF NOT EXISTS ry_cltrid TEXT;
ALTER TABLE provision_domain_redeem ALTER COLUMN domain_name SET NOT NULL;

ALTER TABLE provision_domain_delete ADD COLUMN IF NOT EXISTS ry_cltrid TEXT;
ALTER TABLE provision_domain_delete ADD COLUMN IF NOT EXISTS domain_name FQDN NOT NULL;

ALTER TABLE provision_domain_update ADD COLUMN IF NOT EXISTS ry_cltrid TEXT;
ALTER TABLE provision_domain_update ADD COLUMN IF NOT EXISTS domain_id UUID REFERENCES domain ON DELETE CASCADE;

-- rename name column to domain_name in provision_domain table
DO $$
BEGIN
    IF EXISTS(
        SELECT *
        FROM information_schema.columns
        WHERE table_name='provision_domain' and column_name='name'
    )
      THEN
        ALTER TABLE IF EXISTS provision_domain RENAME COLUMN name TO domain_name;
    END IF;

    IF EXISTS(
        SELECT *
        FROM information_schema.columns
        WHERE table_name='provision_domain_update' and column_name='name'
    )
      THEN
        ALTER TABLE IF EXISTS provision_domain_update RENAME COLUMN name TO domain_name;
    END IF;
END $$;


-- drop provision_domain_name_idx 
DROP INDEX IF EXISTS provision_domain_name_idx;
CREATE UNIQUE INDEX ON provision_domain(domain_name)
  WHERE 
       status_id = tc_id_from_name('provision_status','pending')
    OR status_id = tc_id_from_name('provision_status','processing')
    OR status_id = tc_id_from_name('provision_status','completed')
  ;


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
        domain_name,
        accreditation_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES(
        v_delete_domain.domain_id,
        v_delete_domain.domain_name,
        v_delete_domain.accreditation_id,
        v_delete_domain.tenant_customer_id,
        v_delete_domain.order_metadata,
        ARRAY[NEW.id]
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
      domain_name,
      registration_period,
      accreditation_id,
      accreditation_tld_id,
      tenant_customer_id,
      auto_renew,
      order_metadata,
      order_item_plan_ids
    ) VALUES(
      v_create_domain.domain_name,
      v_create_domain.registration_period,
      v_create_domain.accreditation_id,
      v_create_domain.accreditation_tld_id,
      v_create_domain.tenant_customer_id,
      v_create_domain.auto_renew,
      v_create_domain.order_metadata,
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
    domain_name,
    period,
    accreditation_id,
    tenant_customer_id,
    current_expiry_date,
    order_metadata,
    order_item_plan_ids
  ) VALUES(
    v_renew_domain.domain_id,
    v_renew_domain.domain_name,
    v_renew_domain.period,
    v_renew_domain.accreditation_id,
    v_renew_domain.tenant_customer_id,
    v_renew_domain.current_expiry_date,
    v_renew_domain.order_metadata,
    ARRAY[NEW.id]
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
    domain_id,
    domain_name,
    tenant_customer_id,
    accreditation_id,
    order_metadata,
    order_item_plan_ids
    ) VALUES(
    v_redeem_domain.domain_id,
    v_redeem_domain.domain_name,
    v_redeem_domain.tenant_customer_id,
    v_redeem_domain.accreditation_id,
    v_redeem_domain.order_metadata,
    ARRAY[NEW.id]
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain         RECORD;
    _contact_exists         BOOLEAN;
    _contact_provisioned    BOOLEAN;
    _thin_registry          BOOLEAN;
BEGIN
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
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
    JOIN v_tenant_customer vtc ON vtc.id = v_update_domain.tenant_customer_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_update_domain.accreditation_tld_id
    WHERE va.key = 'tld.lifecycle.is_thin_registry'
      AND va.tld_id = vat.tld_id
      AND va.tenant_id = vtc.tenant_id;

    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
    AND pc.accreditation_id = v_update_domain.accreditation_id;

    IF FOUND OR _thin_registry THEN
        -- contact has already been provisioned, we can mark this as complete.
        UPDATE update_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;
    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids
        ) VALUES(
            NEW.reference_id,
            v_update_domain.accreditation_id,
            v_update_domain.tenant_customer_id,
            ARRAY[NEW.id]
        );
    END IF;
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
            domain_id,
            domain_name,
            auth_info,
            hosts,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            auto_renew,
            order_metadata,
            order_item_plan_ids
        ) VALUES(
            v_update_domain.domain_id,
            v_update_domain.domain_name,
            v_update_domain.auth_info,
            v_update_domain.hosts,
            v_update_domain.accreditation_id,
            v_update_domain.accreditation_tld_id,
            v_update_domain.tenant_customer_id,
            v_update_domain.auto_renew,
            v_update_domain.order_metadata,
            ARRAY[NEW.id]
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
    d.domain_name AS name,
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
    pr.domain_name AS domain_name,
    pr.current_expiry_date AS expiry_date,
    pr.period  AS period,
    pr.order_metadata AS order_metadata
  INTO v_renew
  FROM provision_domain_renew pr 
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
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
    JOIN domain d ON d.id=pr.domain_id
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
    pd.domain_name AS domain_name,
    pr.order_metadata AS order_metadata
  INTO v_delete
  FROM provision_domain_delete pd 
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
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

-- function: provision_domain_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_success() RETURNS TRIGGER AS $$
DECLARE
  s_id UUID;
BEGIN

  SELECT id
  INTO s_id
  FROM domain_status ds
  WHERE ds.name = 'active';

  -- domain 
  INSERT INTO domain(
    id,
    tenant_customer_id,
    accreditation_tld_id,
    name,
    auth_info,
    roid,
    ry_created_date,
    ry_expiry_date,
    expiry_date,
    status_id,
    auto_renew
  ) (
    SELECT 
      pd.id,    -- domain id
      pd.tenant_customer_id,
      pd.accreditation_tld_id,
      pd.domain_name,
      pd.pw,
      pd.roid,
      COALESCE(pd.ry_created_date,pd.created_date),
      COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%d years',pd.registration_period)::INTERVAL),
      COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%d years',pd.registration_period)::INTERVAL),
      s_id as status_id,
      pd.auto_renew
    FROM provision_domain pd
    WHERE id = NEW.id
  );

  -- contact association
  INSERT INTO domain_contact(
    domain_id,
    contact_id,
    domain_contact_type_id,
    handle
  ) (
    SELECT
      pdc.provision_domain_id,
      pdc.contact_id,
      pdc.contact_type_id,
      pc.handle
    FROM provision_domain_contact pdc
    JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
    WHERE pdc.provision_domain_id = NEW.id
  );


  -- host association
  INSERT INTO domain_host(
    domain_id,
    host_id
  ) (
    SELECT 
      provision_domain_id,
      host_id
    FROM provision_domain_host 
    WHERE provision_domain_id = NEW.id
  );


  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
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
        job_id = job_create(
        v_domain.tenant_customer_id,
        'provision_domain_update',
        NEW.id,
        TO_JSONB(v_domain.*)
    ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
DECLARE
    v_domain_id UUID;
BEGIN

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
    SELECT
      NEW.domain_id,
      pdc.contact_id,
      pdc.contact_type_id,
      pc.handle
    FROM provision_domain_update_contact pdc
    JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
    WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
      DO UPDATE SET contact_id = EXCLUDED.contact_id;

    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            NEW.domain_id,
            h.id
        FROM ONLY host h
        WHERE h.name IN (SELECT UNNEST(NEW.hosts))
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete removed hosts
    DELETE FROM
        domain_host dh
    USING
        host h
    WHERE
        NEW.hosts IS NOT NULL
        AND h.name NOT IN (SELECT UNNEST(NEW.hosts))
        AND dh.domain_id = NEW.domain_id
        AND dh.host_id = h.id;

    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew)
    WHERE d.id = NEW.domain_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_status_update()
-- description: called instead of update on v_provision_domain view and sets the status
CREATE OR REPLACE FUNCTION provision_status_update() RETURNS TRIGGER AS $$
BEGIN

  EXECUTE 
    FORMAT('UPDATE %s SET status_id=$1 WHERE id=$2', NEW.reference_table)
    USING NEW.status_id, NEW.id;

  RETURN NEW;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE VIEW v_provision_domain AS 
SELECT
  pd.id,
  pd.accreditation_id,
  a.name as accreditation_name,
  pd.tenant_customer_id, 
  pd.domain_name AS domain_name,
  pd.ry_cltrid,
  pd.status_id,
  'provision_domain' AS reference_table
FROM provision_domain pd
JOIN accreditation a ON a.id = pd.accreditation_id
  
  UNION

SELECT
  pdu.id,
  pdu.accreditation_id,
  a.name as accreditation_name,
  pdu.tenant_customer_id,
  pdu.domain_name AS domain_name,
  pdu.ry_cltrid,
  pdu.status_id,
  'provision_domain_update' AS reference_table
FROM provision_domain_update pdu
JOIN accreditation a ON a.id = pdu.accreditation_id

  UNION

SELECT
  pdd.id,
  pdd.accreditation_id,
  a.name as accreditation_name,
  pdd.tenant_customer_id,
  pdd.domain_name AS domain_name,
  pdd.ry_cltrid,
  pdd.status_id,
  'provision_domain_delete' AS reference_table
FROM provision_domain_delete pdd
JOIN accreditation a ON a.id = pdd.accreditation_id

  UNION

SELECT
  pdr.id,
  pdr.accreditation_id,
  a.name as accreditation_name,
  pdr.tenant_customer_id,
  pdr.domain_name AS domain_name,
  pdr.ry_cltrid,
  pdr.status_id,
  'provision_domain_renew' AS reference_table
FROM provision_domain_renew pdr
JOIN accreditation a ON a.id = pdr.accreditation_id

  UNION

SELECT
  pdr.id,
  pdr.accreditation_id,
  a.name as accreditation_name,
  pdr.tenant_customer_id,
  pdr.domain_name AS domain_name,
  pdr.ry_cltrid,
  pdr.status_id,
  'provision_domain_redeem' AS reference_table
FROM provision_domain_redeem pdr
JOIN accreditation a ON a.id = pdr.accreditation_id;


DROP TRIGGER IF EXISTS v_provision_domain_tg ON v_provision_domain;

CREATE TRIGGER v_provision_domain_tg INSTEAD OF UPDATE ON v_provision_domain
    FOR EACH ROW EXECUTE PROCEDURE provision_status_update();
