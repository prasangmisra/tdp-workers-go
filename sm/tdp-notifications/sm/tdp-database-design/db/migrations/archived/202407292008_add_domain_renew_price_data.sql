------------------------------------------------------------202407292008_add_domain_renew_price_data.sql------------------------------------------------------------ 
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
  cd.auto_renew,
  cd.locks,
  cd.auth_info,
  cd.created_date,
  cd.updated_date,
  cd.tags,
  cd.metadata
FROM order_item_create_domain cd
  JOIN "order" o ON o.id=cd.order_id  
  JOIN v_order_type ot ON ot.id = o.type_id
  JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
  JOIN order_status s ON s.id = o.status_id
  JOIN v_accreditation_tld at ON at.accreditation_tld_id = cd.accreditation_tld_id    
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
  rd.current_expiry_date,
  rd.created_date,
  rd.updated_date
FROM order_item_renew_domain rd
  JOIN "order" o ON o.id=rd.order_id  
  JOIN v_order_type ot ON ot.id = o.type_id
  JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
  JOIN order_status s ON s.id = o.status_id
  JOIN v_accreditation_tld at ON at.accreditation_tld_id = rd.accreditation_tld_id    
  JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=rd.name -- domain from the same tenant_customer
;


-- function: provision_domain_job()
-- description: creates the job to create the domain
CREATE OR REPLACE FUNCTION provision_domain_job() RETURNS TRIGGER AS $$
DECLARE
  v_domain     RECORD;
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
    SELECT JSONB_AGG(data) AS data
    FROM
      (SELECT JSONB_BUILD_OBJECT(
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
  ), 
  price AS (
    SELECT
      JSONB_BUILD_OBJECT(
        'amount', voip.price, 
        'currency', voip.currency_code, 
        'fraction', voip.currency_fraction
    ) AS data
    FROM v_order_item_price voip
    JOIN v_order_create_domain vocd ON voip.order_item_id = vocd.order_item_id AND voip.order_id = vocd.order_id
    WHERE vocd.domain_name = NEW.domain_name
    ORDER BY vocd.created_date DESC
    LIMIT 1
  )
  SELECT
    NEW.id AS provision_contact_id,
    tnc.id AS tenant_customer_id,
    d.domain_name AS name,
    d.registration_period,
    d.pw AS pw,
    contacts.data AS contacts,
    hosts.data AS nameservers,
    price.data AS price,
    TO_JSONB(a.*) AS accreditation,
    TO_JSONB(vat.*) AS accreditation_tld,
    d.order_metadata AS metadata
  INTO v_domain
  FROM provision_domain d
    JOIN contacts ON TRUE
    JOIN hosts ON TRUE
    LEFT JOIN price ON TRUE
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
  WHERE d.id = NEW.id;

  UPDATE provision_domain SET job_id = job_submit(
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
  WITH price AS (
    SELECT
      JSONB_BUILD_OBJECT(
        'amount', voip.price, 
        'currency', voip.currency_code, 
        'fraction', voip.currency_fraction
    ) AS data
    FROM v_order_item_price voip
    JOIN v_order_renew_domain vord ON voip.order_item_id = vord.order_item_id AND voip.order_id = vord.order_id
    WHERE vord.domain_name = NEW.domain_name
    ORDER BY vord.created_date DESC
    LIMIT 1
  )
  SELECT 
    NEW.id AS provision_domain_renew_id,
    tnc.id AS tenant_customer_id,
    TO_JSONB(a.*) AS accreditation,
    pr.domain_name AS domain_name,
    pr.current_expiry_date AS expiry_date,
    pr.period  AS period,
    price.data AS price,
    pr.order_metadata AS metadata
  INTO v_renew
  FROM provision_domain_renew pr
    LEFT JOIN price ON TRUE
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
