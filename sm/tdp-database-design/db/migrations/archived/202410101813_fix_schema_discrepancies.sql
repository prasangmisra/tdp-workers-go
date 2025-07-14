-- Not used any more
DROP TRIGGER IF EXISTS aa_order_prevent_if_domain_does_not_exist_tg ON order_item_delete_domain;

-- adds condition of checking old status
DROP TRIGGER IF EXISTS validate_transfer_domain_plan_tg ON transfer_in_domain_plan;
CREATE TRIGGER validate_transfer_domain_plan_tg
    AFTER UPDATE ON transfer_in_domain_plan
    FOR EACH ROW WHEN (
      OLD.validation_status_id <> NEW.validation_status_id
      AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
      AND NEW.provision_order = 1
    )
    EXECUTE PROCEDURE validate_transfer_domain_plan();

-- adding order metadata
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

-- adding triggers to validation tables
\i triggers.ddl
