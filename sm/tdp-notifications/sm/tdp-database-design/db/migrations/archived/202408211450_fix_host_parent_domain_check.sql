CREATE OR REPLACE FUNCTION check_and_populate_host_parent_domain(host RECORD, order_type TEXT, order_host_id UUID) RETURNS VOID AS $$
DECLARE
    v_parent_domain RECORD;
BEGIN
    -- get host parent domain
    v_parent_domain := get_host_parent_domain(host);

    IF v_parent_domain IS NULL THEN
        RAISE EXCEPTION 'Cannot % host ''%''; permission denied', order_type, host.name;
    END IF;

    -- update order host
    UPDATE order_host SET name = host.name, domain_id = v_parent_domain.id WHERE id = order_host_id;
END;
$$ LANGUAGE plpgsql;
