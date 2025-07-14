DROP VIEW IF EXISTS v_accreditation_tld;
CREATE OR REPLACE VIEW v_accreditation_tld AS
    SELECT
        a.tenant_id              AS tenant_id,
        tn.name                  AS tenant_name,
        a.id                     AS accreditation_id,
        a.name                   AS accreditation_name,
        at.id                    AS accreditation_tld_id,
        t.id                     AS tld_id,
        t.name                   AS tld_name,
        p.name                   AS provider_name,
        p.id                     AS provider_id,
        pi.id                    AS provider_instance_id,
        pi.name                  AS provider_instance_name,
        pi.is_proxy              AS is_proxy,
        at.is_default            AS is_default,
        r.id                     AS registry_id,
        r.name                   AS registry_name
    FROM accreditation a 
        JOIN tenant tn ON tn.id = a.tenant_id
        JOIN accreditation_tld at ON at.accreditation_id = a.id 
        JOIN provider_instance_tld pit ON pit.id = at.provider_instance_tld_id 
            AND pit.service_range @> NOW()
        JOIN provider_instance pi ON pi.id=pit.provider_instance_id AND a.provider_instance_id = pi.id 
        JOIN provider p ON p.id = pi.provider_id     
        JOIN tld t ON t.id = pit.tld_id 
        JOIN registry r ON r.id=t.registry_id
;


DROP VIEW IF EXISTS v_accreditation;
CREATE OR REPLACE VIEW v_accreditation AS 
    SELECT
        a.tenant_id              AS tenant_id,
        a.id                     AS accreditation_id,
        pi.id                    AS provider_instance_id,
        p.id                     AS provider_id,
        tn.name                  AS tenant_name,
        a.name                   AS accreditation_name,
        p.name                   AS provider_name,
        pi.name                  AS provider_instance_name,
        pi.is_proxy              AS is_proxy,
        a.registrar_id           AS registrar_id
    FROM accreditation a 
        JOIN tenant tn ON tn.id = a.tenant_id 
        JOIN provider_instance pi ON pi.id=a.provider_instance_id
        JOIN provider p ON p.id = pi.provider_id
;


DROP VIEW IF EXISTS v_provider_instance_order_item_strategy;
CREATE OR REPLACE VIEW v_provider_instance_order_item_strategy AS 
    -- default strategy
    WITH default_strategy AS (
        SELECT 
            t.id AS type_id,
            o.id AS object_id,
            s.provision_order,
            s.is_validation_required
        FROM order_item_strategy s 
            JOIN order_item_object o ON o.id = s.object_id
            JOIN order_type t ON t.id = s.order_type_id
        WHERE s.provider_instance_id IS NULL
    )
    SELECT 
        p.name      AS provider_name,
        p.id        AS provider_id,
        pi.id       AS provider_instance_id,
        pi.name     AS provider_instance_name,
        dob.name    AS object_name,
        dob.id      AS object_id,
        ot.id       AS order_type_id,
        ot.name     AS order_type_name,
        prod.id        AS product_id,
        prod.name      AS product_name,
        COALESCE(s.provision_order,ds.provision_order) AS provision_order,
        CASE WHEN s.id IS NULL THEN TRUE ELSE FALSE END AS is_default,
        COALESCE(s.is_validation_required, ds.is_validation_required) AS is_validation_required
    FROM provider_instance pi 
        JOIN default_strategy ds ON TRUE
        JOIN provider p ON p.id = pi.provider_id
        JOIN order_item_object dob ON dob.id = ds.object_id 
        JOIN order_type ot ON ds.type_id = ot.id
        JOIN product prod ON prod.id = ot.product_id 
        LEFT JOIN order_item_strategy s
            ON  s.provider_instance_id = pi.id 
                AND ot.id = s.order_type_id 
                AND s.object_id = dob.id
    ORDER BY 1,4,5,7;
;


DROP VIEW IF EXISTS v_order_item_strategy;
CREATE OR REPLACE VIEW v_order_item_strategy AS 
    -- default strategy
    WITH default_strategy AS (
        SELECT 
            t.id AS type_id,
            o.id AS object_id,
            s.provision_order,
            s.is_validation_required
        FROM order_item_strategy s 
            JOIN order_item_object o ON o.id = s.object_id
            JOIN order_type t ON t.id = s.order_type_id
        WHERE s.provider_instance_id IS NULL
    )
    SELECT 
        dob.name    AS object_name,
        dob.id      AS object_id,
        ot.id       AS order_type_id,
        ot.name     AS order_type_name,
        prod.id        AS product_id,
        prod.name      AS product_name,
        COALESCE(s.provision_order,ds.provision_order) AS provision_order,
        CASE WHEN s.id IS NULL THEN TRUE ELSE FALSE END AS is_default,
        COALESCE(s.is_validation_required, ds.is_validation_required) AS is_validation_required
    FROM default_strategy ds
        JOIN order_item_object dob ON dob.id = ds.object_id 
        JOIN order_type ot ON ds.type_id = ot.id
        JOIN product prod ON prod.id = ot.product_id 
        LEFT JOIN order_item_strategy s
            ON  ot.id = s.order_type_id 
                AND s.object_id = dob.id
    ORDER BY 1,4,5,7;
;


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
  cd.launch_data,
  cd.auth_info,
  cd.secdns_max_sig_life,
  cd.uname,
  cd.language,
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
    d.id AS domain_id
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


CREATE OR REPLACE VIEW v_order_delete_contact AS
SELECT
    dc.id AS order_item_id,
    dc.order_id AS order_id,
    dc.contact_id,
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
    tc.name

FROM order_item_delete_contact dc
         JOIN "order" o ON o.id=dc.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
;


CREATE OR REPLACE VIEW v_order_update_contact AS
SELECT
    uc.id AS order_item_id,
    uc.order_id AS order_id,
    uc.contact_id AS contact_id,
    uc.order_contact_id AS order_contact_id,
    uc.reuse_behavior AS reuse_behavior,
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
FROM order_item_update_contact uc
    JOIN order_contact oc ON oc.id = uc.order_contact_id
    JOIN contact_type ct ON ct.id = oc.type_id
    LEFT JOIN order_contact_postal cp ON cp.contact_id = oc.id AND NOT cp.is_international
    JOIN "order" o ON o.id=uc.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;



CREATE OR REPLACE VIEW v_order AS 
SELECT 
  o.id AS order_id,
  p.id AS product_id,
  ot.id AS order_type_id,
  osp.id AS order_path_id,
  os.id AS order_status_id,
  tc.id AS tenant_customer_id,
  t.id AS tenant_id,
  c.id AS customer_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  osp.name AS order_path_name,
  os.name AS order_status_name,
  t.name AS tenant_name,
  c.name AS customer_name,
  os.is_final AS order_status_is_final,
  os.is_success AS order_status_is_success,
  o.created_date,
  o.updated_date,
  o.updated_date-o.created_date AS elapsed
FROM "order" o
  JOIN order_status os ON os.id = o.status_id
  JOIN order_status_path osp ON osp.id = o.path_id
  JOIN order_type ot ON ot.id = o.type_id 
  JOIN product p ON p.id=ot.product_id
  JOIN tenant_customer tc ON tc.id = o.tenant_customer_id 
  JOIN tenant t ON t.id = tc.tenant_id 
  JOIN customer c ON c.id = tc.customer_id 
;

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
    LEFT OUTER JOIN order_hosting_certificate chcr ON ch.certificate_id = chcr.id
    JOIN "order" o ON o.id=ch.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id;

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

DROP VIEW IF EXISTS v_order_create_host;
CREATE OR REPLACE VIEW v_order_create_host AS
SELECT
    ch.id AS order_item_id,
    ch.order_id AS order_id,
    ch.host_id AS host_id,
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
    tc.name AS customer_name,
    oh.tags,
    oh.metadata
FROM order_item_create_host ch
    JOIN order_host oh ON oh.id = ch.host_id
    JOIN "order" o ON o.id=ch.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;

DROP VIEW IF EXISTS v_order_update_host;
CREATE OR REPLACE VIEW v_order_update_host AS
SELECT
    uh.id AS order_item_id,
    uh.order_id AS order_id,
    uh.host_id AS host_id,
    uh.new_host_id AS new_host_id,
    h.name AS host_name,
    d.id AS domain_id,
    d.name AS domain_name,
    vat.accreditation_id,
    vat.accreditation_tld_id,
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
    tc.name AS customer_name
FROM order_item_update_host uh
    JOIN ONLY host h ON h.id = uh.host_id
    LEFT JOIN domain d ON d.id = h.domain_id
    LEFT JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN "order" o ON o.id=uh.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;

DROP VIEW IF EXISTS v_order_delete_host;
CREATE OR REPLACE VIEW v_order_delete_host AS
SELECT
    dh.id AS order_item_id,
    dh.order_id AS order_id,
    dh.host_id AS host_id,
    dh.host_name AS host_name,
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
    tc.name AS customer_name
FROM order_item_delete_host dh
    JOIN ONLY host h ON h.id = dh.host_id
    JOIN "order" o ON o.id=dh.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
;

DROP VIEW IF EXISTS v_order_item_price;
CREATE OR REPLACE VIEW v_order_item_price AS
SELECT
    oip.order_item_id,
    oip.price,
    o.id AS order_id,
    o.tenant_customer_id,
    c.id AS currency_type_id,
    c.name AS currency_type_code,
    c.descr AS currency_type_descr,
    c.fraction AS currency_type_fraction,
    p.name AS product_name,
    ot.name AS order_type_name
FROM order_item_price oip
JOIN currency_type c ON c.id = oip.currency_type_id
JOIN order_item oi ON oi.id = oip.order_item_id
JOIN "order" o ON o.id = oi.order_id
JOIN order_type ot ON ot.id = o.type_id 
JOIN product p ON p.id=ot.product_id
;

DROP VIEW IF EXISTS v_order_transfer_in_domain;
CREATE OR REPLACE VIEW v_order_transfer_in_domain AS 
SELECT
  tid.id AS order_item_id,
  tid.order_id AS order_id,
  tid.accreditation_tld_id,
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
  tid.name AS domain_name,
  tid.transfer_period,
  tid.auth_info,
  tid.tags,
  tid.metadata,
  tid.created_date,
  tid.updated_date
FROM order_item_transfer_in_domain tid
  JOIN "order" o ON o.id=tid.order_id
  JOIN v_order_type ot ON ot.id = o.type_id
  JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
  JOIN order_status s ON s.id = o.status_id
  JOIN v_accreditation_tld at ON at.accreditation_tld_id = tid.accreditation_tld_id
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

\i host/post-views.ddl
\i tld_config/post_views.ddl
