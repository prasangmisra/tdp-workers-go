DROP VIEW IF EXISTS v_order_create_domain,v_order_redeem_domain,v_order_renew_domain,v_order_delete_domain,
    v_order_update_domain,v_order_create_host,v_order_update_host,v_attribute,v_accreditation_tld;

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
    cd.locks
FROM order_item_create_domain cd
         JOIN "order" o ON o.id=cd.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
         JOIN v_accreditation_tld at ON at.accreditation_tld_id = cd.accreditation_tld_id
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
    at.accreditation_id
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
    rd.current_expiry_date
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
    ud.hosts,
    ud.auto_renew,
    ud.locks
FROM order_item_update_domain ud
         JOIN "order" o ON o.id=ud.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
         JOIN v_accreditation_tld at ON at.accreditation_tld_id = ud.accreditation_tld_id
         JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=ud.name
;

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

CREATE OR REPLACE VIEW v_attribute AS

WITH RECURSIVE categories AS (
    SELECT id,name,descr FROM attr_category WHERE parent_id IS NULL
    UNION
    SELECT c.id,p.name || '.' || c.name,c.descr FROM attr_category c JOIN categories p ON p.id = c.parent_id
)

SELECT
    vat.tenant_id,
    vat.tenant_name,
    vat.tld_name AS tld_name,
    vat.tld_id AS tld_id,
    c.name AS path,
    c.id AS category_id,
    k.id AS key_id,
    avt.data_type,
    avt.name AS data_type_name,
    c.name || '.' || k.name AS key,
    COALESCE(vtld.value,vpi.value,vp.value,vpr.value,v.value,k.default_value) AS value,
    COALESCE(vtld.is_default,vpi.is_default,vp.is_default,vpr.is_default,v.is_default,TRUE) AS is_default
FROM v_accreditation_tld vat
         JOIN categories c ON TRUE
         JOIN attr_key k ON k.category_id = c.id
         JOIN attr_value_type avt ON avt.id = k.value_type_id
         LEFT JOIN v_attr_value v
                   ON  v.tenant_id = vat.tenant_id
                       AND v.key_id = k.id
                       AND COALESCE(v.tld_id,v.provider_instance_id,v.provider_id,v.registry_id) IS NULL
         LEFT JOIN v_attr_value vtld ON vtld.key_id = k.id AND vat.tld_id = vtld.tld_id
         LEFT JOIN v_attr_value vpi ON vpi.key_id = k.id AND vat.provider_instance_id = vpi.provider_instance_id
         LEFT JOIN v_attr_value vp ON vp.key_id = k.id AND vat.provider_id = vp.provider_id
         LEFT JOIN v_attr_value vpr ON vpr.key_id = k.id AND vat.registry_id = vpr.registry_id
ORDER BY tld_name,key;



---------------------------------------------------------------------------------------

DROP TRIGGER IF EXISTS order_prevent_if_create_domain_contact_does_not_exist_tg ON create_domain_contact;
DROP TRIGGER IF EXISTS order_prevent_if_update_domain_contact_does_not_exist_tg ON update_domain_contact;

CREATE OR REPLACE FUNCTION order_prevent_if_create_domain_contact_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT
            1
        FROM
            contact c
                JOIN v_order_create_domain cd ON cd.order_item_id = NEW.create_domain_id
        WHERE
            c.id = NEW.order_contact_id
          AND c.tenant_customer_id = cd.tenant_customer_id
          AND c.deleted_date IS NULL)
    THEN
        RAISE EXCEPTION 'order_contact_id % does not exist in either contact or order_contact table.', NEW.order_contact_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION order_prevent_if_update_domain_contact_does_not_exist() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT
            1
        FROM
            contact c
                JOIN v_order_update_domain cd ON cd.order_item_id = NEW.update_domain_id
        WHERE
            c.id = NEW.order_contact_id
          AND c.tenant_customer_id = cd.tenant_customer_id
          AND c.deleted_date IS NULL)
    THEN
        RAISE EXCEPTION 'order_contact_id % does not exist in either contact or order_contact table.', NEW.order_contact_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER order_prevent_if_create_domain_contact_does_not_exist_tg
    BEFORE INSERT ON create_domain_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_create_domain_contact_does_not_exist();

CREATE TRIGGER order_prevent_if_update_domain_contact_does_not_exist_tg
    BEFORE INSERT ON update_domain_contact
    FOR EACH ROW
    WHEN (NEW.order_contact_id IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_update_domain_contact_does_not_exist();



CREATE OR REPLACE FUNCTION get_accreditation_tld_by_name(fqdn TEXT, tc_id UUID) RETURNS RECORD AS $$
DECLARE
    v_tld_name    TEXT;
    v_acc_tld     RECORD;
BEGIN
    v_tld_name := tld_part(fqdn);

    SELECT v_accreditation_tld.*, tnc.id as tenant_customer_id INTO v_acc_tld
    FROM v_accreditation_tld
             JOIN tenant_customer tnc ON tnc.tenant_id= v_accreditation_tld.tenant_id
    WHERE tld_name = v_tld_name
      AND tnc.id =tc_id
      AND is_default;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    RETURN v_acc_tld;
END;
$$ LANGUAGE PLPGSQL;
