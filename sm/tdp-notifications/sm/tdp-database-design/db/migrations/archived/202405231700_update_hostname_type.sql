DROP TRIGGER IF EXISTS order_prevent_if_nameserver_does_not_exist_tg ON order_item_update_domain;
DROP TRIGGER IF EXISTS order_prevent_if_nameservers_count_is_invalid_tg ON order_item_update_domain;

DROP VIEW IF EXISTS v_order_update_domain;


ALTER TABLE order_item_update_domain ALTER COLUMN hosts TYPE FQDN[];



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

CREATE OR REPLACE TRIGGER order_prevent_if_nameserver_does_not_exist_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW WHEN (NEW.hosts IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_nameserver_does_not_exist();

CREATE OR REPLACE TRIGGER order_prevent_if_nameservers_count_is_invalid_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW WHEN (NEW.hosts IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_nameservers_count_is_invalid();


CREATE OR REPLACE FUNCTION validate_name_fqdn() RETURNS TRIGGER AS $$
BEGIN
    IF NOT ValidFQDN(NEW.name) THEN
        RAISE EXCEPTION 'Name % is not a valid FQDN', NEW.name;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_name_fqdn
    BEFORE INSERT ON order_host
    FOR EACH ROW WHEN(NEW.name <> '')EXECUTE FUNCTION validate_name_fqdn();

