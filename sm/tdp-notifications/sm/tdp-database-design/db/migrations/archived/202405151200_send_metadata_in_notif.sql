BEGIN;

--
-- update job_event_notify
--
CREATE OR REPLACE FUNCTION job_event_notify() RETURNS TRIGGER AS
$$
DECLARE
    _payload JSONB;
BEGIN
  SELECT
    JSONB_BUILD_OBJECT(
      'job_id',j.job_id,
      'type',j.job_type_name,
      'status',j.job_status_name,
      'reference_id',j.reference_id,
      'reference_table',j.reference_table,
      'routing_key',j.routing_key,
      'metadata',
      CASE WHEN j.data ? 'metadata' 
      THEN
      (j.data -> 'metadata')
      ELSE
      '{}'::JSONB
      END
    )
  INTO _payload
  FROM v_job j
  WHERE job_id = NEW.id;
  
  PERFORM notify_event('job_event','job_event_notify',_payload::TEXT);
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;

--
-- update provision_contact_job
--

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
    NEW.order_metadata AS metadata
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

--
-- update provision contact delete job
--

CREATE OR REPLACE FUNCTION provision_contact_delete_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id      UUID;
    _child_jobs         RECORD;
    v_contact           RECORD;
BEGIN
    SELECT job_create(
                   NEW.tenant_customer_id,
                   'provision_contact_delete_group',
                   NEW.id,
                   to_jsonb(NULL::jsonb)
           ) INTO _parent_job_id;
    UPDATE provision_contact_delete SET job_id= _parent_job_id WHERE id = NEW.id;
    FOR _child_jobs IN
        SELECT *
        FROM provision_contact_delete pcd
        WHERE pcd.parent_id = NEW.id
        LOOP
            SELECT
                TO_JSONB(a.*) AS accreditation,
                _child_jobs.handle AS handle,
                _child_jobs.order_metadata AS metadata
            INTO v_contact
            FROM v_accreditation a
            WHERE a.accreditation_id = _child_jobs.accreditation_id;
            UPDATE provision_contact_delete SET job_id=job_submit(
                    _child_jobs.tenant_customer_id,
                    'provision_contact_delete',
                    _child_jobs.id,
                    to_jsonb(v_contact.*),
                    _parent_job_id,
                    FALSE
                     ) WHERE id = _child_jobs.id;
        END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- update provision domain job
--

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
    d.order_metadata AS metadata
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

--
-- update domain renew job function
--

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
    pr.order_metadata AS metadata
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

--
-- update provision domain redeem
--

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
    pr.order_metadata AS metadata
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

--
-- update provision domain delete job function
--

CREATE OR REPLACE FUNCTION provision_domain_delete_job() RETURNS TRIGGER AS $$
DECLARE
  v_delete     RECORD;
BEGIN
  SELECT 
    NEW.id AS provision_domain_delete_id,
    tnc.id AS tenant_customer_id,
    TO_JSONB(a.*) AS accreditation,
    pd.domain_name AS domain_name,
    pd.order_metadata AS metadata
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
-- update provision domain update job function
--

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
        d.order_metadata AS metadata
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

--
-- update provision host job function
--

CREATE OR REPLACE FUNCTION provision_host_job() RETURNS TRIGGER AS $$
DECLARE
  v_host     RECORD;
BEGIN
  SELECT
    NEW.id AS provision_host_id,
    NEW.tenant_customer_id AS tenant_customer_id,
    jsonb_get_host_by_id(h.id) AS host,
    TO_JSONB(va.*) AS accreditation,
    NEW.order_metadata AS metadata
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

--
-- update provision host update job function
--

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
    NEW.order_metadata AS metadata
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

--
-- update provision hosting create job function
--

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
          ph.order_metadata AS metadata,
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

--
-- update provision hosting update job
--

CREATE OR REPLACE FUNCTION provision_hosting_update_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
    BEGIN
        SELECT
            phu.hosting_id as hosting_id,
            vtnc.id AS tenant_customer_id,
            phu.order_metadata AS metadata,
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

--
-- update provision hosting delete job function
--

CREATE OR REPLACE FUNCTION provision_hosting_delete_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
    BEGIN
        SELECT
            NEW.id as provision_hosting_delete_id,
            vtnc.id AS tenant_customer_id,
            phd.order_metadata AS metadata,
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

COMMIT;