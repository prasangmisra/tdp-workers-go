-- Change public.domain.name type from text to public.fqdn

DROP VIEW IF EXISTS public.v_domain;
DROP VIEW IF EXISTS v_order_create_host;
DROP VIEW IF EXISTS v_order_delete_domain;
DROP VIEW IF EXISTS v_order_redeem_domain;
DROP VIEW IF EXISTS v_order_renew_domain ;
DROP VIEW IF EXISTS v_order_transfer_away_domain ;
DROP VIEW IF EXISTS v_order_update_domain ;
DROP VIEW IF EXISTS v_order_update_host ;

ALTER TABLE public.DOMAIN ALTER COLUMN name TYPE public.fqdn ;


CREATE OR REPLACE VIEW v_domain AS
SELECT
  d.*,
  rgp.id AS rgp_status_id,
  rgp.epp_name AS rgp_epp_status,
  lock.names AS locks
FROM domain d
LEFT JOIN LATERAL (
    SELECT
        rs.epp_name,
        drs.id,
        drs.expiry_date
    FROM domain_rgp_status drs
    JOIN rgp_status rs ON rs.id = drs.status_id
    WHERE drs.domain_id = d.id
    ORDER BY created_date DESC
    LIMIT 1
) rgp ON rgp.expiry_date >= NOW()
LEFT JOIN LATERAL (
    SELECT
        JSON_AGG(vdl.name) AS names
    FROM v_domain_lock vdl
    WHERE vdl.domain_id = d.id AND NOT vdl.is_internal
) lock ON TRUE;


CREATE OR REPLACE VIEW v_order_create_host AS
SELECT
    ch.id AS order_item_id,
    ch.order_id AS order_id,
    ch.host_id AS host_id,
    oh.name as host_name,
    d.id AS domain_id,
    d.name AS domain_name,
    vat.accreditation_id,
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
    LEFT JOIN order_host_addr oha ON oha.host_id = oh.id
    JOIN domain d ON d.id = oh.domain_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN "order" o ON o.id=ch.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;

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
    ud.auto_renew,
    ud.locks,
    ud.secdns_max_sig_life
FROM order_item_update_domain ud
     JOIN "order" o ON o.id=ud.order_id
     JOIN v_order_type ot ON ot.id = o.type_id
     JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
     JOIN order_status s ON s.id = o.status_id
     JOIN v_accreditation_tld at ON at.accreditation_tld_id = ud.accreditation_tld_id
     JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=ud.name
;

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
    at.accreditation_id,
    rd.created_date,
    rd.updated_date
FROM order_item_redeem_domain rd
    JOIN "order" o ON o.id=rd.order_id  
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = rd.accreditation_tld_id
    JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=rd.name
;


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


CREATE OR REPLACE VIEW v_order_transfer_away_domain AS
SELECT
  tad.id AS order_item_id,
  tad.order_id AS order_id,
  tad.accreditation_tld_id,
  o.metadata AS order_metadata,
  o.tenant_customer_id,
  o.type_id,
  o.customer_user_id,
  o.status_id,
  s.name AS status_name,
  s.descr AS status_descr,
  s.is_final AS status_is_final,
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
  ts.name AS transfer_status_name,
  tad.transfer_status_id,
  tad.requested_by,
  tad.requested_date,
  tad.action_by,
  tad.action_date,
  tad.expiry_date,
  tad.auth_info,
  tad.metadata
FROM order_item_transfer_away_domain tad
  JOIN "order" o ON o.id=tad.order_id
  JOIN v_order_type ot ON ot.id = o.type_id
  JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
  JOIN order_status s ON s.id = o.status_id
  JOIN v_accreditation_tld at ON at.accreditation_tld_id = tad.accreditation_tld_id
  JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=tad.name
  JOIN transfer_status ts ON ts.id = tad.transfer_status_id
;

CREATE OR REPLACE VIEW v_order_update_host AS
SELECT
    uh.id AS order_item_id,
    uh.order_id AS order_id,
    uh.host_id AS host_id,
    uh.new_host_id AS new_host_id,
    oh.name AS host_name,
    d.id AS domain_id,
    d.name AS domain_name,
    vat.accreditation_id,
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
FROM order_item_update_host uh
    JOIN order_host oh ON oh.id = uh.new_host_id
    LEFT JOIN order_host_addr oha ON oha.host_id = oh.id
    JOIN domain d ON d.id = oh.domain_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN "order" o ON o.id=uh.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;




--\i domain\views.ddl
--\i post-views.ddl