
-- function: check_and_populate_host_parent_domain()
-- description: checks and populates host parent domain
CREATE OR REPLACE FUNCTION check_and_populate_host_parent_domain(order_host_id UUID)
    RETURNS VOID AS $$
DECLARE
    v_parent_domain        RECORD;
    v_order_host         RECORD;
BEGIN
    -- Get host information
    SELECT * INTO v_order_host
    FROM ONLY order_host
    WHERE id = order_host_id;

    -- Extract the parent domain name from the host name
    v_parent_domain := get_host_parent_domain(v_order_host.name, v_order_host.tenant_customer_id);

    IF v_parent_domain IS NULL THEN
        RAISE EXCEPTION 'Parent domain not found';
    END IF;

    -- Check if the host name is the same as its parent domain name
    IF v_parent_domain.name = v_order_host.name THEN
        RAISE EXCEPTION 'Host names such as % that could be confused with a domain name cannot be accepted', v_order_host.name;
    END IF;


    -- Update the order host with the parent domain ID
    UPDATE order_host
    SET domain_id = v_parent_domain.id
    WHERE id = order_host_id;

END;
$$ LANGUAGE plpgsql;


-- function: check_if_tld_supports_host_object()
-- description: checks if tld supports host object or not
CREATE OR REPLACE FUNCTION check_if_tld_supports_host_object(order_type TEXT, order_host_id UUID) RETURNS VOID AS $$
DECLARE
    v_host_object_supported  BOOLEAN;
BEGIN
    SELECT get_tld_setting(
                   p_key=>'tld.order.host_object_supported',
                   p_accreditation_tld_id=>d.accreditation_tld_id)
    INTO v_host_object_supported
    FROM order_host oh
             JOIN domain d ON d.id = oh.domain_id
    WHERE oh.id = order_host_id;

    IF NOT v_host_object_supported THEN
        IF order_type = 'create' THEN
            RAISE EXCEPTION 'Host create not supported';
        ELSE
            RAISE EXCEPTION 'Host update not supported; use domain update on parent domain';
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;