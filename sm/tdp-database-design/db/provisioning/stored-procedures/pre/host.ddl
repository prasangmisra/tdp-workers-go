-- function: provision_host_job()
-- description: creates the job to create the host
CREATE OR REPLACE FUNCTION provision_host_job() RETURNS TRIGGER AS $$
DECLARE
    v_host     RECORD;
BEGIN
    SELECT
        NEW.id AS provision_host_id,
        NEW.host_id,
        NEW.tenant_customer_id AS tenant_customer_id,
        NEW.name AS host_name,
        NEW.addresses AS host_addrs,
        TO_JSONB(va.*) AS accreditation,
        get_accreditation_tld_by_name(NEW.name, NEW.tenant_customer_id) AS host_accreditation_tld,
        FALSE AS host_ip_required_non_auth, -- should come from registry settings
        NEW.order_metadata AS metadata
    INTO v_host
    FROM v_accreditation va
    WHERE va.accreditation_id = NEW.accreditation_id;

    UPDATE provision_host SET job_id=job_submit(
        NEW.tenant_customer_id,
        'provision_host_create',
        NEW.id,
        TO_JSONB(v_host.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_host_update_job()
-- description: creates host update parent and child jobs
CREATE OR REPLACE FUNCTION provision_host_update_job() RETURNS TRIGGER AS $$
DECLARE
    v_host     RECORD;
BEGIN
    SELECT
        NEW.id AS provision_host_update_id,
        NEW.tenant_customer_id AS tenant_customer_id,
        NEW.host_id AS host_id,
        NEW.name AS host_name,
        NEW.addresses AS host_new_addrs,
        get_host_addrs(NEW.host_id) AS host_old_addrs,
        TO_JSONB(va.*) AS accreditation,
        NEW.order_metadata AS metadata
    INTO v_host
    FROM v_accreditation va
    WHERE va.accreditation_id = NEW.accreditation_id;

    UPDATE provision_host_update SET job_id=job_submit(
        v_host.tenant_customer_id,
        'provision_host_update',
        NEW.id,
        to_jsonb(v_host.*)
    ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_host_delete_job()
-- description: creates the job to delete the host
CREATE OR REPLACE FUNCTION provision_host_delete_job() RETURNS TRIGGER AS $$
DECLARE
    v_host  RECORD;
BEGIN
    SELECT
        NEW.id AS provision_host_delete_id,
        NEW.host_id AS host_id,
        NEW.name AS host_name,
        NEW.tenant_customer_id AS tenant_customer_id,
        get_tld_setting(
            p_key=>'tld.order.host_delete_rename_allowed',
            p_tld_name=>tld_part(NEW.name),
            p_tenant_id=>va.tenant_id
        )::BOOL AS host_delete_rename_allowed,
        get_tld_setting(
            p_key=>'tld.order.host_delete_rename_domain',
            p_tld_name=>tld_part(NEW.name),
            p_tenant_id=>va.tenant_id
        )::TEXT AS host_delete_rename_domain,
        TO_JSONB(va.*) AS accreditation,
        NEW.order_metadata AS metadata
    INTO v_host
    FROM v_accreditation va
    WHERE va.accreditation_id = NEW.accreditation_id;

    UPDATE provision_host_delete SET job_id=job_submit(
        NEW.tenant_customer_id,
        'provision_host_delete',
        NEW.id,
        TO_JSONB(v_host.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
