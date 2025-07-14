-- function: get_host_addrs()
-- description: returns a sorted array containing all addresses an host
CREATE OR REPLACE FUNCTION get_host_addrs(p_id UUID) RETURNS INET[] AS $$
DECLARE
    addrs INET[];
BEGIN
    SELECT INTO addrs ARRAY_AGG(address ORDER BY address)
    FROM ONLY host_addr
    WHERE host_id = p_id;

    RETURN COALESCE(addrs, '{}'); -- return empty array Instead of NULL
END;
$$ LANGUAGE plpgsql STABLE;


-- function: get_order_host_addrs()
-- description: returns a sorted array containing all addresses an order host
CREATE OR REPLACE FUNCTION get_order_host_addrs(p_id UUID) RETURNS INET[] AS $$
DECLARE
    addrs INET[];
BEGIN
    SELECT INTO addrs ARRAY_AGG(address ORDER BY address)
    FROM ONLY order_host_addr
    WHERE host_id = p_id;

    RETURN COALESCE(addrs, '{}'); -- return empty array Instead of NULL
END;
$$ LANGUAGE plpgsql STABLE;


DROP FUNCTION IF EXISTS get_host_parent_domain(host RECORD);
DROP FUNCTION IF EXISTS check_and_populate_host_parent_domain(host RECORD, order_type TEXT, order_host_id UUID);

CREATE OR REPLACE FUNCTION get_host_parent_domain(p_host_name TEXT, p_tenant_customer_id uuid) RETURNS RECORD AS $$
DECLARE
    v_domain RECORD;
    v_partial_domain TEXT;
    dot_pos INT;
BEGIN
    -- Start by checking the full host name
    v_partial_domain := p_host_name;

    LOOP
        -- Check if the current partial domain exists
        SELECT * INTO v_domain
        FROM domain
        WHERE name = v_partial_domain
          AND tenant_customer_id = p_tenant_customer_id;

        IF FOUND THEN
            EXIT;
        END IF;

        -- Find the position of the first dot
        dot_pos := POSITION('.' IN v_partial_domain);

        -- If no more dots are found, exit the loop
        IF dot_pos = 0 THEN
            RETURN NULL;
        END IF;

        -- Trim the domain segment before the first dot
        v_partial_domain := SUBSTRING(v_partial_domain FROM dot_pos + 1);
    END LOOP;

    RETURN v_domain;
END;
$$ LANGUAGE plpgsql;


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

CREATE OR REPLACE FUNCTION plan_create_domain_provision_host() RETURNS TRIGGER AS $$
DECLARE
    v_dc_host                                   RECORD;
    v_create_domain                             RECORD;
    v_host_object_supported                     BOOLEAN;
    v_host_parent_domain                        RECORD;
    v_host_accreditation                        RECORD;
BEGIN
    -- Fetch domain creation host details
    SELECT cdn.*,oh."name",oh.tenant_customer_id,oh.domain_id
    INTO v_dc_host
    FROM create_domain_nameserver cdn
             JOIN order_host oh ON oh.id=cdn.host_id
    WHERE
        cdn.id = NEW.reference_id;

    IF v_dc_host IS NULL THEN
        RAISE EXCEPTION 'reference id % not found in create_domain_nameserver table', NEW.reference_id;
    END IF;

    -- Load the order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    -- Get value of host_object_supported	flag
    SELECT get_tld_setting(
                   p_key=>'tld.order.host_object_supported',
                   p_tld_id=>v_create_domain.tld_id
           )
    INTO v_host_object_supported;

    -- Host provisioning will be skipped
    -- if the host object is not supported for domain accreditation
    IF v_host_object_supported IS FALSE THEN
        UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
        RETURN NEW;
    END IF;

    -- Host Accreditation
    v_host_accreditation := get_accreditation_tld_by_name(v_dc_host.name, v_dc_host.tenant_customer_id);

    IF v_host_accreditation IS NOT NULL THEN
        IF v_create_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
            -- Host and domain are under same accreditation, run additional checks

            v_host_parent_domain := get_host_parent_domain(v_dc_host.name,
                                                                  v_dc_host.tenant_customer_id);

            IF v_host_parent_domain is NULL THEN
                RAISE EXCEPTION 'Parent domain not found';
            END IF;

            IF v_host_parent_domain.name = v_dc_host.name THEN
                RAISE EXCEPTION 'Host names such as % that could be confused with a domain name cannot be accepted', v_dc_host.name;
            END IF;

            -- Check if there are addrs or not
            IF get_order_host_addrs(v_dc_host.host_id) = '{}'::INET[] THEN
                -- ip addresses are required to provision host under parent tld
                RAISE EXCEPTION 'Missing IP addresses for hostname';
            END IF;
        END IF;
    END IF;

    INSERT INTO provision_host(
        accreditation_id,
        host_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
                 v_create_domain.accreditation_id,
                 v_dc_host.host_id,
                 v_create_domain.tenant_customer_id,
                 v_create_domain.order_metadata,
                 ARRAY[NEW.id]
             ) ON CONFLICT (host_id,accreditation_id)
        DO UPDATE
        SET order_item_plan_ids = provision_host.order_item_plan_ids || EXCLUDED.order_item_plan_ids;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            error_message TEXT;
        BEGIN
            -- Capture the error message
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;

            -- Update the plan with the captured error message
            UPDATE create_domain_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION plan_create_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_host RECORD;
BEGIN
    -- order information
    SELECT * INTO v_create_host
    FROM v_order_create_host
    WHERE order_item_id = NEW.order_item_id;

    -- Check if there are addrs or not
    IF get_order_host_addrs(v_create_host.host_id) = '{}'::INET[] THEN
        UPDATE create_host_plan
        SET result_message = 'Missing IP addresses for hostname',
            status_id = tc_id_from_name('order_item_plan_status', 'failed')
        WHERE id = NEW.id;
        RETURN new;
    END IF;

    -- insert into provision_host with normal flow
    INSERT INTO provision_host(
        accreditation_id,
        host_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
                 v_create_host.accreditation_id,
                 v_create_host.host_id,
                 v_create_host.tenant_customer_id,
                 v_create_host.order_metadata,
                 ARRAY[NEW.id]
             );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION plan_update_host_provision() RETURNS TRIGGER AS $$
DECLARE
    v_update_host       RECORD;
    v_order_host_addrs  INET[];
BEGIN
    -- order information
    SELECT * INTO v_update_host
    FROM v_order_update_host
    WHERE order_item_id = NEW.order_item_id;

    v_order_host_addrs := get_order_host_addrs(v_update_host.new_host_id);

    -- Check if there are addrs or not
    IF v_order_host_addrs = '{}'::INET[] THEN
        UPDATE update_host_plan
        SET result_message = 'Missing IP addresses for hostname',
            status_id = tc_id_from_name('order_item_plan_status', 'failed')
        WHERE id = NEW.id;

        RETURN new;
    END IF;

    -- check addresses
    IF NOT get_host_addrs(v_update_host.host_id) = v_order_host_addrs THEN
        -- insert into provision_host_update with normal flow
        INSERT INTO provision_host_update(
            tenant_customer_id,
            host_id,
            new_host_id,
            accreditation_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES (
                     v_update_host.tenant_customer_id,
                     v_update_host.host_id,
                     v_update_host.new_host_id,
                     v_update_host.accreditation_id,
                     v_update_host.order_metadata,
                     ARRAY [NEW.id]
                 );
    ELSE
        -- complete the order item
        UPDATE update_host_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_host_parent_domain_customer() RETURNS TRIGGER AS $$
DECLARE
    v_order_host_id UUID;
BEGIN
    IF TG_TABLE_NAME = 'order_item_create_host' THEN
        v_order_host_id = NEW.host_id;
    ELSIF TG_TABLE_NAME = 'order_item_update_host' THEN
        v_order_host_id = NEW.new_host_id;
    ELSE
        RAISE EXCEPTION 'unsupported order type for host product';
    END IF;

    PERFORM check_and_populate_host_parent_domain(v_order_host_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_host_update_success()
-- description: updates the host once the provision job completes
CREATE OR REPLACE FUNCTION provision_host_update_success() RETURNS TRIGGER AS $$
DECLARE
    new_host_addrs INET[];
BEGIN
    -- get host addrs
    new_host_addrs := get_order_host_addrs(NEW.new_host_id);

    -- add new addrs
    INSERT INTO host_addr (host_id, address)
    SELECT NEW.host_id, unnest(new_host_addrs)
    ON CONFLICT (host_id, address) DO NOTHING;

    -- remove old addrs
    DELETE FROM host_addr
    WHERE host_id = NEW.host_id AND (address != ALL(new_host_addrs));

    -- set host parent domain
    UPDATE host h
    SET domain_id = oh.domain_id
    FROM order_host oh
    WHERE h.id = NEW.host_id AND oh.id = NEW.new_host_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
