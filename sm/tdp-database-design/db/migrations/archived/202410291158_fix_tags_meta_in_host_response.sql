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

CREATE OR REPLACE FUNCTION plan_create_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_host           RECORD;
    v_order_host_addrs      INET[];
    v_host_parent_domain    RECORD;
    v_host_object_supported BOOLEAN;
    v_host_accreditation    RECORD;
BEGIN
    -- order information
    SELECT * INTO v_create_host
    FROM v_order_create_host
    WHERE order_item_id = NEW.order_item_id;

    v_host_parent_domain := get_host_parent_domain(v_create_host.host_name, v_create_host.tenant_customer_id);

    IF v_host_parent_domain IS NULL THEN
        -- provision host locally only
        INSERT INTO host (SELECT h.* FROM host h WHERE h.id = v_create_host.host_id);
        INSERT INTO host_addr (SELECT ha.* FROM host_addr ha WHERE ha.host_id = v_create_host.host_id);

        -- mark plan as completed to complete the order
        UPDATE create_host_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    v_order_host_addrs := get_order_host_addrs(v_create_host.host_id);

    -- Check if there are addrs or not
    IF v_order_host_addrs = '{}'::INET[] THEN
        UPDATE create_host_plan
        SET result_message = 'Missing IP addresses for hostname',
            status_id = tc_id_from_name('order_item_plan_status', 'failed')
        WHERE id = NEW.id;
    
        RETURN NEW;
    END IF;

    -- Get value of host_object_supported flag
    SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_accreditation_tld_id=>v_host_parent_domain.accreditation_tld_id
    )
    INTO v_host_object_supported;

    IF v_host_object_supported IS FALSE THEN
        -- provision host locally only
        INSERT INTO host (SELECT h.* FROM host h WHERE h.id = v_create_host.host_id);
        INSERT INTO host_addr (SELECT ha.* FROM host_addr ha WHERE ha.host_id = v_create_host.host_id);

        UPDATE create_host_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
        WHERE id = NEW.id;
        
        RETURN NEW;
    END IF;

    -- insert into provision_host with normal flow
    INSERT INTO provision_host(
        host_id,
        name,
        domain_id,
        addresses,
        accreditation_id,
        tenant_customer_id,
        order_metadata,
        tags,
        metadata,
        order_item_plan_ids
    ) VALUES (
        v_create_host.host_id,
        v_create_host.host_name,
        v_host_parent_domain.id,
        v_order_host_addrs,
        v_host_parent_domain.accreditation_id,
        v_create_host.tenant_customer_id,
        v_create_host.order_metadata,
        v_create_host.tags,
        v_create_host.metadata,
        ARRAY[NEW.id]
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
