INSERT INTO job_status(name,descr,is_final,is_success,is_cond) VALUES
('created','Job has been created',false,true,false)
ON CONFLICT DO NOTHING;

ALTER TABLE job_type ADD COLUMN IF NOT EXISTS is_noop BOOLEAN NOT NULL DEFAULT FALSE;

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
    'provision_domain_contact_update',
    'Updates contact in domain specific backend',
    NULL, -- the type not implemented yet
    'provision_status',
    'status_id',
    'WorkerJobContactProvision',
    FALSE
),
(
    'provision_contact_update',
    'Groups updates for contact in backends',
    NULL, -- the type not implemented yet
    'provision_status',
    'status_id',
    NULL,
    TRUE
) ON CONFLICT DO NOTHING;

ALTER TABLE job ALTER COLUMN status_id SET DEFAULT tc_id_from_name('job_status','created');
ALTER TABLE job ADD COLUMN IF NOT EXISTS is_hard_fail BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE job ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES job(id);

DROP INDEX IF EXISTS job_parent_id_idx;
CREATE INDEX ON job(parent_id);

--
-- updates the parent job with the status value 
-- according to child jobs and flags.  
--

CREATE OR REPLACE FUNCTION job_parent_status_update() RETURNS TRIGGER AS $$
DECLARE
_job_status            RECORD;
_parent_job            RECORD;
BEGIN

  -- no parent; nothing to do
  IF NEW.parent_id IS NULL THEN 
    RETURN NEW;
  END IF;

  SELECT * INTO _job_status FROM job_status WHERE id = NEW.status_id;

  -- child job not final; nothing to do
  IF NOT _job_status.is_final THEN 
    RETURN NEW;
  END IF;

  -- parent has final status; nothing to do
  SELECT * INTO _parent_job FROM v_job WHERE job_id = NEW.parent_id;
  IF _parent_job.job_status_is_final THEN
    RETURN NEW;
  END IF;

  -- child job failed hard; fail parent
  IF NOT _job_status.is_success AND NEW.is_hard_fail THEN
    UPDATE job SET status_id = tc_id_from_name('job_status', 'failed') WHERE id = NEW.parent_id;
    RETURN NEW;
  END IF;

  -- check for unfinished children jobs
  PERFORM TRUE FROM v_job WHERE job_parent_id = NEW.parent_id AND NOT job_status_is_final;

  IF NOT FOUND THEN
  
    PERFORM TRUE FROM v_job WHERE job_parent_id = NEW.parent_id AND job_status_is_success;

    IF FOUND THEN
      UPDATE job SET status_id = tc_id_from_name('job_status', 'submitted') WHERE id = NEW.parent_id;
    ELSE
      -- all children jobs had failed
      UPDATE job SET status_id = tc_id_from_name('job_status', 'failed') WHERE id = NEW.parent_id;
    END IF;  
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


--
-- job_create is used to create a job.
--

DROP FUNCTION job_create;
CREATE OR REPLACE FUNCTION job_create(
  _tenant_customer_id   UUID,
  _job_type             TEXT,
  _reference_id         UUID,
  _data                 JSONB DEFAULT '{}'::JSONB,
  _job_parent_id        UUID DEFAULT NULL,
  _is_hard_fail         BOOLEAN DEFAULT TRUE
) RETURNS UUID AS $$
DECLARE
  _new_job_id      UUID;
BEGIN

  EXECUTE 'INSERT INTO job(
    tenant_customer_id,
    type_id,
    reference_id,
    data,
    parent_id,
    is_hard_fail
  ) VALUES($1,$2,$3,$4,$5,$6) RETURNING id'
  INTO
    _new_job_id
  USING
    _tenant_customer_id,
    tc_id_from_name('job_type',_job_type),
    _reference_id,
    _data,
    _job_parent_id,
    _is_hard_fail;

  RETURN _new_job_id;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION job_create IS
'creates a new job given a tenant_customer_id 
UUID,job_type TEXT,reference_id UUID';

--
-- job_submit is used to create a job and submit it right away.
--

CREATE OR REPLACE FUNCTION job_submit(
  _tenant_customer_id   UUID,
  _job_type             TEXT,
  _reference_id         UUID,
  _data                 JSONB DEFAULT '{}'::JSONB,
  _job_parent_id        UUID DEFAULT NULL,
  _is_hard_fail         BOOLEAN DEFAULT TRUE
) RETURNS UUID AS $$
DECLARE
  _new_job_id      UUID;
BEGIN

  EXECUTE 'INSERT INTO job(
    tenant_customer_id,
    type_id,
    status_id,
    reference_id,
    data,
    parent_id,
    is_hard_fail
  ) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id'
  INTO
    _new_job_id
  USING
    _tenant_customer_id,
    tc_id_from_name('job_type',_job_type),
    tc_id_from_name('job_status', 'submitted'),
    _reference_id,
    _data,
    _job_parent_id,
    _is_hard_fail;

  RETURN _new_job_id;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION job_submit IS
'submits a new job which given a tenant_customer_id 
UUID,job_type TEXT,reference_id UUID';

--
-- job_complete_noop copletes the job which is of is_noop type
--

CREATE OR REPLACE FUNCTION job_complete_noop() RETURNS TRIGGER AS
$$
DECLARE 
  v_job_type RECORD;
BEGIN

  SELECT * INTO v_job_type FROM job_type WHERE id=NEW.type_id;

  IF v_job_type.is_noop THEN 
    NEW.status_id = tc_id_from_name('job_status','completed');
  END IF;

  RETURN NEW;
END;
$$
LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS job_notify_tg ON job;
CREATE TRIGGER job_notify_tg AFTER INSERT ON job
    FOR EACH ROW WHEN (
            NEW.status_id = tc_id_from_name('job_status','submitted') 
    )
    EXECUTE PROCEDURE job_event_notify();

DROP TRIGGER IF EXISTS job_complete_noop_tg ON job;
CREATE TRIGGER job_complete_noop_tg BEFORE UPDATE ON job 
    FOR EACH ROW WHEN (
            OLD.status_id <> NEW.status_id
            AND NEW.status_id = tc_id_from_name('job_status','submitted')
    )
    EXECUTE PROCEDURE job_complete_noop();

DROP TRIGGER IF EXISTS job_notify_submitted_tg ON job;
CREATE TRIGGER job_notify_submitted_tg AFTER UPDATE ON job 
    FOR EACH ROW WHEN (
            OLD.status_id <> NEW.status_id
            AND NEW.status_id = tc_id_from_name('job_status','submitted')
    )
    EXECUTE PROCEDURE job_event_notify();

DROP TRIGGER IF EXISTS job_parent_status_update_tg ON job;
CREATE TRIGGER job_parent_status_update_tg AFTER UPDATE ON job 
    FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id)
    EXECUTE PROCEDURE job_parent_status_update();


DROP VIEW IF EXISTS v_job;
CREATE OR REPLACE VIEW v_job AS
    SELECT 
        j.id AS job_id,
        j.parent_id AS job_parent_id,
        j.tenant_customer_id,
        js.name AS job_status_name,
        jt.name AS job_type_name,
        j.created_date,
        j.start_date,
        j.end_date,
        j.retry_date,
        j.retry_count,
        j.reference_id,
        jt.reference_table,
        j.result_message AS result_message,
        j.result_data AS result_data,
        j.data AS data,
        TO_JSONB(vtc.*) AS tenant_customer,
        jt.routing_key,
        jt.is_noop AS job_type_is_noop,
        js.is_final AS job_status_is_final,
        js.is_success AS job_status_is_success,
        j.event_id,
        j.is_hard_fail
    FROM job j 
        JOIN job_status js ON j.status_id = js.id 
        JOIN job_type jt ON jt.id = j.type_id
        JOIN v_tenant_customer vtc ON vtc.id = j.tenant_customer_id
;

CREATE OR REPLACE FUNCTION provision_contact_job() RETURNS TRIGGER AS $$
DECLARE
  v_contact     RECORD;
BEGIN

  SELECT 
    NEW.id AS provision_contact_id,
    NEW.tenant_customer_id AS tenant_customer_id,
    jsonb_get_contact_by_id(c.id) AS contact,
    TO_JSONB(a.*) AS accreditation,
    NEW.pw AS pw
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
    job_id = job_submit(
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

  UPDATE provision_domain_renew SET job_id=job_submit(
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

    UPDATE provision_domain_redeem SET job_id=job_submit(
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
    pd.order_metadata AS order_metadata
  INTO v_delete
  FROM provision_domain_delete pd 
    JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
  WHERE pd.id = NEW.id;

  UPDATE provision_domain_delete SET job_id=job_submit(
    v_delete.tenant_customer_id,
    'provision_domain_delete',
    NEW.id,
    TO_JSONB(v_delete.*)
  ) WHERE id = NEW.id;

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
        job_id = job_submit(
        v_domain.tenant_customer_id,
        'provision_domain_update',
        NEW.id,
        TO_JSONB(v_domain.*)
    ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
    TO_JSONB(a.*) AS accreditation
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

-- function: provision_hosting_update_job
-- description: updates a job to update a hosting order
CREATE OR REPLACE FUNCTION provision_hosting_update_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
    BEGIN
        SELECT
            phu.hosting_id as hosting_id,
            vtnc.id AS tenant_customer_id,
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

-- function: provision_hosting_delete_job
-- description: deletes a job to provision a hosting order
CREATE OR REPLACE FUNCTION provision_hosting_delete_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
    BEGIN
        SELECT
            NEW.id as provision_hosting_delete_id,
            vtnc.id AS tenant_customer_id,
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

