-- function: plan_create_host_provision()
-- description: create a host based on the plan
CREATE OR REPLACE FUNCTION plan_create_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_host           RECORD;
    v_order_host_addrs      INET[];
    v_host_parent_domain    RECORD;
    v_host_object_supported BOOLEAN;
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

    -- If there are IPv6 addresses, check if tld supports IPv6.
    IF NOT is_host_ipv6_supported(v_order_host_addrs, v_host_parent_domain.accreditation_tld_id) THEN
        UPDATE create_host_plan
        SET result_message = 'IPv6 addresses are not supported by the ''' || tld_part(v_create_host.host_name) || ''' tld',
            status_id = tc_id_from_name('order_item_plan_status', 'failed')
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


-- function: plan_update_host_provision()
-- description: update a host based on the plan
CREATE OR REPLACE FUNCTION plan_update_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_update_host           RECORD;
    v_order_host_addrs      INET[];
    v_host_object_supported BOOLEAN;
    v_host_parent_domain    RECORD;
    v_is_host_provisioned   BOOLEAN DEFAULT TRUE;
BEGIN
    -- order information
    SELECT * INTO v_update_host
    FROM v_order_update_host
    WHERE order_item_id = NEW.order_item_id;

    v_order_host_addrs := get_order_host_addrs(v_update_host.new_host_id);

    -- Check if addreses provided
    IF v_order_host_addrs = '{}'::INET[] THEN
        UPDATE update_host_plan
        SET result_message = 'Missing IP addresses for hostname',
            status_id = tc_id_from_name('order_item_plan_status', 'failed')
        WHERE id = NEW.id;

        RETURN new;
    END IF;

    IF v_update_host.domain_id IS NULL THEN
        v_host_parent_domain := get_host_parent_domain(v_update_host.host_name, v_update_host.tenant_customer_id);

        IF v_host_parent_domain IS NULL THEN
            -- update host locally

            -- add new addrs
            INSERT INTO host_addr (host_id, address)
            SELECT v_update_host.host_id, unnest(v_order_host_addrs)
            ON CONFLICT (host_id, address) DO NOTHING;

            -- remove old addrs
            DELETE FROM host_addr
            WHERE host_id = v_update_host.host_id AND (address != ALL(v_order_host_addrs));

            -- mark plan as completed to complete the order
            UPDATE update_host_plan
                SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
            WHERE id = NEW.id;

            UPDATE ONLY host h
            SET updated_date = NEW.updated_date
            WHERE NEW.updated_date IS NOT NULL AND h.id = v_update_host.host_id;

            RETURN NEW;
        END IF;

        -- parent domain was created after host, this implies host does not exist yet at registry
        v_is_host_provisioned := FALSE;

        v_update_host.domain_id := v_host_parent_domain.id;
        v_update_host.domain_name := v_host_parent_domain.name;
        v_update_host.accreditation_id = v_host_parent_domain.accreditation_id;
        v_update_host.accreditation_tld_id = v_host_parent_domain.accreditation_tld_id;
    END IF; 

    IF get_host_addrs(v_update_host.host_id) = v_order_host_addrs THEN
        -- nothing to update complete the order item
        UPDATE update_host_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- Get value of host_object_supported flag
    SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_accreditation_tld_id=>v_update_host.accreditation_tld_id
    )
    INTO v_host_object_supported;

    IF v_host_object_supported IS FALSE THEN
        -- update host locally

        -- add new addrs
        INSERT INTO host_addr (host_id, address)
        SELECT v_update_host.host_id, unnest(v_order_host_addrs)
        ON CONFLICT (host_id, address) DO NOTHING;

        -- remove old addrs
        DELETE FROM host_addr
        WHERE host_id = v_update_host.host_id AND (address != ALL(v_order_host_addrs));

        -- set host parent domain if needed
        UPDATE ONLY host
        SET domain_id = v_update_host.domain_id
        WHERE id = v_update_host.host_id AND domain_id IS NULL;

        UPDATE ONLY host h
        SET updated_date = NEW.updated_date
        WHERE NEW.updated_date IS NOT NULL AND h.id = v_update_host.host_id;

        -- mark plan as completed to complete the order
        UPDATE update_host_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
        WHERE id = NEW.id;
        
        RETURN NEW;
    END IF;

    -- If there are IPv6 addresses, check if tld supports IPv6.
    IF NOT is_host_ipv6_supported(v_order_host_addrs, v_update_host.accreditation_tld_id) THEN
        UPDATE update_host_plan
        SET result_message = 'IPv6 addresses are not supported by the ''' || tld_part(v_update_host.host_name) || ''' tld',
            status_id = tc_id_from_name('order_item_plan_status', 'failed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    IF v_is_host_provisioned IS FALSE THEN
        -- host to be created

        INSERT INTO provision_host(
            host_id,
            name,
            domain_id,
            addresses,
            accreditation_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES (
            v_update_host.host_id,
            v_update_host.host_name,
            v_update_host.domain_id,
            v_order_host_addrs,
            v_update_host.accreditation_id,
            v_update_host.tenant_customer_id,
            v_update_host.order_metadata,
            ARRAY [NEW.id]
        );
    ELSE
        -- insert into provision_host_update with normal flow
        INSERT INTO provision_host_update(
            host_id,
            name,
            domain_id,
            addresses,
            accreditation_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES (
            v_update_host.host_id,
            v_update_host.host_name,
            v_update_host.domain_id,
            v_order_host_addrs,
            v_update_host.accreditation_id,
            v_update_host.tenant_customer_id,
            v_update_host.order_metadata,
            ARRAY [NEW.id]
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_delete_host_provision()
-- description: delete a host based on the plan
CREATE OR REPLACE FUNCTION plan_delete_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_host               RECORD;
    v_host_parent_domain        RECORD;
BEGIN
    -- order information
    SELECT * INTO v_delete_host
    FROM v_order_delete_host
    WHERE order_item_id = NEW.order_item_id;

    v_host_parent_domain := get_host_parent_domain(v_delete_host.host_name, v_delete_host.tenant_customer_id);

    IF v_host_parent_domain IS NULL THEN
        -- delete host locally only
        DELETE FROM ONLY host where id=v_delete_host.host_id;

        -- mark plan as completed to complete the order
        UPDATE delete_host_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- insert into provision_host with normal flow
    INSERT INTO provision_host_delete(
        host_id,
        name,
        domain_id,
        accreditation_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_delete_host.host_id,
        v_delete_host.host_name,
        v_host_parent_domain.id,
        v_host_parent_domain.accreditation_id,
        v_delete_host.tenant_customer_id,
        v_delete_host.order_metadata,
        ARRAY [NEW.id]
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
