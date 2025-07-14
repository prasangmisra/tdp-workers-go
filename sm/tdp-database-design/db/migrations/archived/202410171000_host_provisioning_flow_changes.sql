-- adding accreditation data
DROP VIEW IF EXISTS v_domain;
CREATE OR REPLACE VIEW v_domain AS
SELECT
  d.*,
  act.accreditation_id,
  rgp.id AS rgp_status_id,
  rgp.epp_name AS rgp_epp_status,
  lock.names AS locks
FROM domain d
JOIN accreditation_tld act ON act.id = d.accreditation_tld_id
LEFT JOIN LATERAL (
    SELECT
        rs.epp_name,
        drs.id,
        drs.expiry_date
    FROM domain_rgp_status drs
    JOIN rgp_status rs ON rs.id = drs.status_id
    WHERE drs.domain_id = d.id
    ORDER BY created_date DESC
    LIMIT 1
) rgp ON rgp.expiry_date >= NOW()
LEFT JOIN LATERAL (
    SELECT
        JSON_AGG(vdl.name) AS names
    FROM v_domain_lock vdl
    WHERE vdl.domain_id = d.id AND NOT vdl.is_internal
) lock ON TRUE;

-- selecting from v_domain view instead of domain table
CREATE OR REPLACE FUNCTION get_host_parent_domain(p_host_name TEXT, p_tenant_customer_id uuid) RETURNS RECORD AS $$
DECLARE
    v_parent_domain RECORD;
    v_partial_domain TEXT;
    dot_pos INT;
BEGIN
    -- Start by checking the full host name
    v_partial_domain := p_host_name;

    LOOP
        -- Check if the current partial domain exists
        SELECT * INTO v_parent_domain
        FROM v_domain
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

    RETURN v_parent_domain;
END;
$$ LANGUAGE plpgsql;

-- not used any more
DROP FUNCTION IF EXISTS jsonb_get_host_by_id(p_id UUID);

-- validation logic was changed
DROP TRIGGER IF EXISTS a_validate_host_parent_domain_customer_tg ON order_item_create_host;
DROP TRIGGER IF EXISTS order_prevent_if_host_object_unsupported_tg ON order_item_create_host;

DROP TRIGGER IF EXISTS a_validate_host_parent_domain_customer_tg ON order_item_update_host;
DROP TRIGGER IF EXISTS order_prevent_if_host_object_unsupported_tg ON order_item_update_host;

DROP FUNCTION IF EXISTS validate_host_parent_domain_customer();
DROP FUNCTION IF EXISTS order_prevent_if_host_object_unsupported();

CREATE OR REPLACE FUNCTION plan_create_domain_provision_host() RETURNS TRIGGER AS $$
DECLARE
    v_host                      RECORD;
    v_order_host                RECORD;
    v_create_domain             RECORD;
    v_host_accreditation        RECORD;
    v_host_parent_domain        RECORD;
    v_order_host_addrs          INET[];
BEGIN
    -- Fetch domain creation host details
    SELECT oh.*
    INTO v_order_host
    FROM order_host oh
        JOIN create_domain_nameserver cdn ON cdn.host_id=oh.id
    WHERE
        cdn.id = NEW.reference_id;

    -- Load the order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    -- Check host already in database for customer
    SELECT * INTO v_host
    FROM ONLY host
    WHERE name = v_order_host.name AND tenant_customer_id = v_order_host.tenant_customer_id;

    IF FOUND then
        -- use existing data in database
        v_order_host := v_host;
       	v_order_host_addrs := get_host_addrs(v_order_host.id);
    ELSE
        v_order_host_addrs := get_order_host_addrs(v_order_host.id);
    END IF;

    -- Host Accreditation
    v_host_accreditation := get_accreditation_tld_by_name(v_order_host.name, v_order_host.tenant_customer_id);
    IF v_host_accreditation IS NOT NULL THEN
        IF v_create_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
            -- Host and domain are under same accreditation, run additional checks

            v_host_parent_domain := get_host_parent_domain(v_order_host.name, v_order_host.tenant_customer_id);

            IF v_host_parent_domain IS NULL THEN
                RAISE EXCEPTION 'Parent domain not found for %', v_order_host.name;
            END IF;

            -- populate parent domain id 
            v_order_host.domain_id := v_host_parent_domain.id;

            IF v_host_parent_domain.name = v_order_host.name THEN
                RAISE EXCEPTION 'Host names such as % that could be confused with a domain name cannot be accepted', v_order_host.name;
            END IF;

            -- Check if there are addrs or not
            IF v_order_host_addrs = '{}'::INET[] THEN
                -- ip addresses are required to provision host under parent tld
                RAISE EXCEPTION 'Missing IP addresses for hostname %', v_order_host.name;
            END IF;
        END IF;
    END IF;

    -- Provision the host
    INSERT INTO provision_host(
        host_id,
        name,
        domain_id,
        addresses,
        tags,
        metadata,
        accreditation_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_order_host.id,
        v_order_host.name,
        v_order_host.domain_id,
        v_order_host_addrs,
        v_order_host.tags,
        v_order_host.metadata,
        v_create_domain.accreditation_id,
        v_create_domain.tenant_customer_id,
        v_create_domain.order_metadata,
        ARRAY[NEW.id]
    );

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


CREATE OR REPLACE FUNCTION plan_update_domain_provision_host() RETURNS TRIGGER AS $$
DECLARE
    v_host                      RECORD;
    v_order_host                RECORD;
    v_update_domain             RECORD;
    v_host_accreditation        RECORD;
    v_host_parent_domain        RECORD;
    v_order_host_addrs          INET[];
BEGIN
    -- Fetch domain creation host details
    SELECT oh.*
    INTO v_order_host
    FROM order_host oh
        JOIN update_domain_add_nameserver udan ON udan.host_id=oh.id
    WHERE
        udan.id = NEW.reference_id;

    -- Load the order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- Check host already in database for customer
    SELECT * INTO v_host
    FROM ONLY host
    WHERE name = v_order_host.name AND tenant_customer_id = v_order_host.tenant_customer_id;

    IF FOUND then
        -- use existing data in database
        v_order_host := v_host;
       	v_order_host_addrs := get_host_addrs(v_order_host.id);
    ELSE
        v_order_host_addrs := get_order_host_addrs(v_order_host.id);
    END IF;

    -- Host Accreditation
    v_host_accreditation := get_accreditation_tld_by_name(v_order_host.name, v_order_host.tenant_customer_id);
    IF v_host_accreditation IS NOT NULL THEN
        IF v_update_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
            -- Host and domain are under same accreditation, run additional checks

            v_host_parent_domain := get_host_parent_domain(v_order_host.name, v_order_host.tenant_customer_id);

            IF v_host_parent_domain IS NULL THEN
                RAISE EXCEPTION 'Parent domain not found for %', v_order_host.name;
            END IF;

            -- populate parent domain id 
            v_order_host.domain_id := v_host_parent_domain.id;

            IF v_host_parent_domain.name = v_order_host.name THEN
                RAISE EXCEPTION 'Host names such as % that could be confused with a domain name cannot be accepted', v_order_host.name;
            END IF;

            -- Check if there are addrs or not
            IF v_order_host_addrs = '{}'::INET[] THEN
                -- ip addresses are required to provision host under parent tld
                RAISE EXCEPTION 'Missing IP addresses for hostname %', v_order_host.name;
            END IF;
        END IF;
    END IF;

    -- Provision the host
    INSERT INTO provision_host(
        host_id,
        name,
        domain_id,
        addresses,
        tags,
        metadata,
        accreditation_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_order_host.id,
        v_order_host.name,
        v_order_host.domain_id,
        v_order_host_addrs,
        v_order_host.tags,
        v_order_host.metadata,
        v_update_domain.accreditation_id,
        v_update_domain.tenant_customer_id,
        v_update_domain.order_metadata,
        ARRAY[NEW.id]
    );

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            error_message TEXT;
        BEGIN
            -- Capture the error message
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;

            -- Update the plan with the captured error message
            UPDATE update_domain_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
END;
$$ LANGUAGE plpgsql;


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
        order_item_plan_ids
    ) VALUES (
        v_create_host.host_id,
        v_create_host.host_name,
        v_host_parent_domain.id,
        v_order_host_addrs,
        v_host_parent_domain.accreditation_id,
        v_create_host.tenant_customer_id,
        v_create_host.order_metadata,
        ARRAY[NEW.id]
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


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
        UPDATE host
        SET domain_id = v_update_host.domain_id
        WHERE id = v_update_host.host_id AND domain_id IS NULL;

        -- mark plan as completed to complete the order
        UPDATE update_host_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
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


CREATE OR REPLACE FUNCTION validate_create_domain_host_plan() RETURNS TRIGGER AS $$
DECLARE
    v_order_host                RECORD;
    v_create_domain             RECORD;
    v_host_object_supported     BOOLEAN;
    v_job_data                  JSONB;
    v_job_id                    UUID;
BEGIN
    -- Fetch domain creation host details
    SELECT oh.*
    INTO v_order_host
    FROM order_host oh
        JOIN create_domain_nameserver cdn ON cdn.host_id=oh.id
    WHERE
        cdn.id = NEW.reference_id;

    IF NOT FOUND THEN
        -- Update the plan with the captured error message
        UPDATE create_domain_plan
        SET result_message = FORMAT('reference id %s not found in create_domain_nameserver table', NEW.reference_id),
            validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- order information
    SELECT
        vocd.*,
        TO_JSONB(a.*) AS accreditation
    INTO v_create_domain
    FROM v_order_create_domain vocd
    JOIN v_accreditation a ON a.accreditation_id = vocd.accreditation_id
    WHERE vocd.order_item_id = NEW.order_item_id;

    -- Get value of host_object_supported flag
    SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_tld_id=>v_create_domain.tld_id,
        p_tenant_id=>v_create_domain.tenant_id
    )
    INTO v_host_object_supported;

    -- Skip host validation if the host object is not supported for domain accreditation.
    IF v_host_object_supported IS FALSE THEN
        UPDATE create_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed'),
                validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;
        
        RETURN NEW;
    END IF;

    v_job_data := jsonb_build_object(
        'host_name', v_order_host.name,
        'order_item_plan_id', NEW.id,
        'accreditation', v_create_domain.accreditation,
        'tenant_customer_id', v_create_domain.tenant_customer_id,
        'order_metadata', v_create_domain.order_metadata
    );

    v_job_id := job_submit(
        v_create_domain.tenant_customer_id,
        'validate_host_available',
        NEW.id,
        v_job_data
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION validate_update_domain_host_plan() RETURNS TRIGGER AS $$
DECLARE
    v_order_host                RECORD;
    v_update_domain             RECORD;
    v_host_object_supported     BOOLEAN;
    v_job_data                  JSONB;
    v_job_id                    UUID;
BEGIN
    -- Fetch domain update host details
    SELECT oh.*
    INTO v_order_host
    FROM order_host oh
        JOIN update_domain_add_nameserver udan ON udan.host_id=oh.id
    WHERE
        udan.id = NEW.reference_id;

    IF NOT FOUND THEN
        -- Update the plan with the captured error message
        UPDATE update_domain_plan
        SET result_message = FORMAT('reference id %s not found in update_domain_add_nameserver table', NEW.reference_id),
            validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'failed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- order information
    SELECT
        voud.*,
        TO_JSONB(a.*) AS accreditation
    INTO v_update_domain
    FROM v_order_update_domain voud
    JOIN v_accreditation a ON a.accreditation_id = voud.accreditation_id
    WHERE voud.order_item_id = NEW.order_item_id;

    -- Get value of host_object_supported flag
    SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_tld_id=>v_update_domain.tld_id,
        p_tenant_id=>v_update_domain.tenant_id
    )
    INTO v_host_object_supported;

    -- Skip host validation if the host object is not supported for domain accreditation.
    IF v_host_object_supported IS FALSE THEN
        UPDATE update_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed'),
                validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    v_job_data := jsonb_build_object(
        'host_name', v_order_host.name,
        'order_item_plan_id', NEW.id,
        'accreditation', v_update_domain.accreditation,
        'tenant_customer_id', v_update_domain.tenant_customer_id,
        'order_metadata', v_update_domain.order_metadata
    );

    v_job_id := job_submit(
        v_update_domain.tenant_customer_id,
        'validate_host_available',
        NEW.id,
        v_job_data
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
    tc.name AS customer_name
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

-- host_id column can have ids for order_host or host tables now
ALTER TABLE IF EXISTS provision_host DROP CONSTRAINT IF EXISTS provision_host_host_id_accreditation_id_key;
ALTER TABLE IF EXISTS provision_host DROP CONSTRAINT IF EXISTS provision_host_host_id_fkey;
ALTER TABLE IF EXISTS provision_host ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE IF EXISTS provision_host ADD COLUMN IF NOT EXISTS domain_id UUID REFERENCES domain;
ALTER TABLE IF EXISTS provision_host ADD COLUMN IF NOT EXISTS addresses INET[];
ALTER TABLE IF EXISTS provision_host ADD COLUMN IF NOT EXISTS tags TEXT[];
ALTER TABLE IF EXISTS provision_host ADD COLUMN IF NOT EXISTS metadata JSONB;

ALTER TABLE IF EXISTS provision_host_update DROP COLUMN IF EXISTS new_host_id;
ALTER TABLE IF EXISTS provision_host_update ADD COLUMN IF NOT EXISTS domain_id UUID REFERENCES domain;
ALTER TABLE IF EXISTS provision_host_update ADD COLUMN IF NOT EXISTS addresses INET[];
ALTER TABLE IF EXISTS provision_host_update ADD COLUMN IF NOT EXISTS name TEXT;

UPDATE provision_host_update phu SET name = h.name FROM ONLY host h WHERE h.id = phu.host_id;

ALTER TABLE IF EXISTS provision_host_update ALTER COLUMN name SET NOT NULL;

-- populate provision_host name before setting that column not nullable
UPDATE provision_host SET name = oh.name
FROM order_host oh WHERE host_id = oh.id;

ALTER TABLE IF EXISTS provision_host ALTER COLUMN name SET NOT NULL;

CREATE OR REPLACE FUNCTION provision_host_success() RETURNS TRIGGER AS $$
DECLARE
BEGIN
    -- create new host if does not exist already
    INSERT INTO host (
        id,
        name,
        domain_id,
        tenant_customer_id,
        tags,
        metadata
    ) VALUES (
        NEW.host_id,
        NEW.name,
        NEW.domain_id,
        NEW.tenant_customer_id,
        NEW.tags,
        NEW.metadata
    ) ON CONFLICT (id)
    DO UPDATE
    -- set parent domain id if was null before
    SET domain_id = COALESCE(host.domain_id, EXCLUDED.domain_id);

    -- add new addresses
    INSERT INTO host_addr (host_id, address)
    SELECT NEW.host_id, unnest(NEW.addresses)
    ON CONFLICT (host_id, address) DO NOTHING;

    -- remove old addrs in case host was created on update
    DELETE FROM host_addr
    WHERE host_id = NEW.host_id AND (address != ALL(NEW.addresses));

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION provision_host_update_success() RETURNS TRIGGER AS $$
DECLARE
    new_host_addrs INET[];
BEGIN

    -- add new addrs
    INSERT INTO host_addr (host_id, address)
    SELECT NEW.host_id, unnest(NEW.addresses)
    ON CONFLICT (host_id, address) DO NOTHING;

    -- remove old addrs
    DELETE FROM host_addr
    WHERE host_id = NEW.host_id AND (address != ALL(NEW.addresses));

    -- set host parent domain if needed
    UPDATE host h
    SET domain_id = NEW.domain_id
    WHERE h.id = NEW.host_id AND h.domain_id IS NULL;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION provision_domain_update_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
    _parent_job_id      UUID;
    v_locks_required_changes JSONB;
BEGIN
    WITH contacts AS(
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                    'type', ct.name,
                    'handle', pc.handle
            )
        ) AS data
        FROM provision_domain_update_contact pdc
            JOIN domain_contact_type ct ON ct.id =  pdc.contact_type_id
            JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
            JOIN provision_status ps ON ps.id = pc.status_id
        WHERE
            ps.is_success AND ps.is_final
            AND pdc.provision_domain_update_id = NEW.id

    ), hosts_add AS(
        SELECT JSONB_AGG(data) AS add
        FROM (
            SELECT
                JSON_BUILD_OBJECT(
                    'name', h.name,
                    'ip_addresses', JSONB_AGG(ha.address)
                ) AS data
            FROM provision_domain_update_add_host pduah
                JOIN ONLY host h ON h.id = pduah.host_id
                LEFT JOIN ONLY host_addr ha ON h.id = ha.host_id
            WHERE pduah.provision_domain_update_id = NEW.id
            GROUP BY h.name
        ) sub_q
    ), hosts_rem AS(
        SELECT  JSONB_AGG(data) AS rem
        FROM (
            SELECT 
                JSON_BUILD_OBJECT(
                    'name', h.name,
                    'ip_addresses', JSONB_AGG(ha.address)
                ) AS data
            FROM provision_domain_update_rem_host pdurh
                JOIN ONLY host h ON h.id = pdurh.host_id
                LEFT JOIN ONLY host_addr ha ON h.id = ha.host_id
            WHERE pdurh.provision_domain_update_id = NEW.id
            GROUP BY h.name
        ) sub_q
    ), secdns_add AS(
        SELECT
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'key_tag', osdd.key_tag,
                    'algorithm', osdd.algorithm,
                    'digest_type', osdd.digest_type,
                    'digest', osdd.digest,
                    'key_data',
                    CASE
                        WHEN osdd.key_data_id IS NOT NULL THEN
                            JSONB_BUILD_OBJECT(
                                'flags', oskd2.flags,
                                'protocol', oskd2.protocol,
                                'algorithm', oskd2.algorithm,
                                'public_key', oskd2.public_key
                            )
                    END
                )
            ) FILTER (WHERE udas.ds_data_id IS NOT NULL) AS ds_data,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'flags', oskd1.flags,
                    'protocol', oskd1.protocol,
                    'algorithm', oskd1.algorithm,
                    'public_key', oskd1.public_key
                )
            ) FILTER (WHERE udas.key_data_id IS NOT NULL) AS key_data
        FROM provision_domain_update_add_secdns pduas
            LEFT JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
            LEFT JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
            LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = udas.key_data_id
            LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id

        WHERE pduas.provision_domain_update_id = NEW.id
        GROUP BY pduas.provision_domain_update_id

    ), secdns_rem AS(
        SELECT
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'key_tag', osdd.key_tag,
                    'algorithm', osdd.algorithm,
                    'digest_type', osdd.digest_type,
                    'digest', osdd.digest,
                    'key_data',
                    CASE
                        WHEN osdd.key_data_id IS NOT NULL THEN
                            JSONB_BUILD_OBJECT(
                                'flags', oskd2.flags,
                                'protocol', oskd2.protocol,
                                'algorithm', oskd2.algorithm,
                                'public_key', oskd2.public_key
                            )
                    END
                )
            ) FILTER (WHERE udrs.ds_data_id IS NOT NULL) AS ds_data,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'flags', oskd1.flags,
                    'protocol', oskd1.protocol,
                    'algorithm', oskd1.algorithm,
                    'public_key', oskd1.public_key
                )
            ) FILTER (WHERE udrs.key_data_id IS NOT NULL) AS key_data
        FROM provision_domain_update_rem_secdns pdurs
            LEFT JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            LEFT JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
            LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = udrs.key_data_id
            LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id

        WHERE pdurs.provision_domain_update_id = NEW.id
        GROUP BY pdurs.provision_domain_update_id
    )
    SELECT
        NEW.id AS provision_domain_update_id,
        tnc.id AS tenant_customer_id,
        d.order_metadata,
        d.domain_name AS name,
        d.auth_info AS pw,
        contacts.data AS contacts,
        TO_JSONB(hosts_add) || TO_JSONB(hosts_rem) AS nameservers,
        JSONB_BUILD_OBJECT(
            'max_sig_life', d.secdns_max_sig_life,
            'add', TO_JSONB(secdns_add),
            'rem', TO_JSONB(secdns_rem)
        ) as secdns,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS metadata,
        va1.value::BOOL AS is_rem_update_lock_with_domain_content_supported,
        va2.value::BOOL AS is_add_update_lock_with_domain_content_supported
    INTO v_domain
    FROM provision_domain_update d
        LEFT JOIN contacts ON TRUE
        LEFT JOIN hosts_add ON TRUE
        LEFT JOIN hosts_rem ON TRUE
        LEFT JOIN secdns_add ON TRUE
        LEFT JOIN secdns_rem ON TRUE
        JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
        JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
        JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
        JOIN v_attribute va1 ON
            va1.tld_id = vat.tld_id AND
            va1.key = 'tld.order.is_rem_update_lock_with_domain_content_supported' AND
            va1.tenant_id = tnc.tenant_id
        JOIN v_attribute va2 ON
            va2.tld_id = vat.tld_id AND
            va2.key = 'tld.order.is_add_update_lock_with_domain_content_supported' AND
            va2.tenant_id = tnc.tenant_id
    WHERE d.id = NEW.id;

    -- Retrieves the required changes for domain locks based on the provided lock configuration.
    SELECT
        JSONB_OBJECT_AGG(
                l.key, l.value::BOOLEAN
        )
    INTO v_locks_required_changes
    FROM JSONB_EACH(NEW.locks) l
             LEFT JOIN v_domain_lock vdl ON vdl.name = l.key AND vdl.domain_id = NEW.domain_id AND NOT vdl.is_internal
    WHERE (NOT l.value::boolean AND vdl.id IS NOT NULL) OR (l.value::BOOLEAN AND vdl.id IS NULL);

    -- If there are required changes for the 'update' lock AND there are other changes to the domain, THEN we MAY need to
    -- create two separate jobs: One job for the 'update' lock and Another job for all other domain changes, Because if
    -- the only change we have is 'update' lock, we can do it in a single job
    IF (v_locks_required_changes ? 'update') AND
       (COALESCE(v_domain.contacts,v_domain.nameservers,v_domain.pw::JSONB)  IS NOT NULL
           OR NOT is_jsonb_empty_or_null(v_locks_required_changes - 'update'))
    THEN
        -- If 'update' lock has false value (remove the lock) and the registry "DOES NOT" support removing that lock with
        -- the other domain changes in a single command, then we need to create two jobs: the first one to remove the
        -- domain lock, and the second one to handle the other domain changes
        IF (v_locks_required_changes->'update')::BOOLEAN IS FALSE AND
           NOT v_domain.is_rem_update_lock_with_domain_content_supported THEN
            -- all the changes without the update lock removal, because first we need to remove the lock on update
            SELECT job_create(
                           v_domain.tenant_customer_id,
                           'provision_domain_update',
                           NEW.id,
                           TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes - 'update')
                   ) INTO _parent_job_id;

            -- Update provision_domain_update table with parent job id
            UPDATE provision_domain_update SET job_id = _parent_job_id  WHERE id=NEW.id;

            -- first remove the update lock so we can do the other changes
            PERFORM job_submit(
                    v_domain.tenant_customer_id,
                    'provision_domain_update',
                    NULL,
                    jsonb_build_object('locks', jsonb_build_object('update', FALSE),
                                       'name',v_domain.name,
                                       'accreditation',v_domain.accreditation,
                                       'accreditation_tld', v_domain.accreditation_tld),
                    _parent_job_id
                    );
            RETURN NEW; -- RETURN

        -- Same thing here, if 'update' lock has true value (add the lock) and the registry DOES NOT support adding that
        -- lock with the other domain changes in a single command, then we need to create two jobs: the first one to
        -- handle the other domain changes and the second one to add the domain lock

        elsif (v_locks_required_changes->'update')::BOOLEAN IS TRUE AND
              NOT v_domain.is_add_update_lock_with_domain_content_supported THEN
            -- here we want to add the lock on update (we will do the changes first then add the lock)
            SELECT job_create(
                           v_domain.tenant_customer_id,
                           'provision_domain_update',
                           NEW.id,
                           jsonb_build_object('locks', jsonb_build_object('update', TRUE),
                                              'name',v_domain.name,
                                              'accreditation',v_domain.accreditation)
                   ) INTO _parent_job_id;

            -- Update provision_domain_update table with parent job id
            UPDATE provision_domain_update SET job_id = _parent_job_id  WHERE id=NEW.id;

            -- Submit child job for all the changes other than domain update lock
            PERFORM job_submit(
                    v_domain.tenant_customer_id,
                    'provision_domain_update',
                    NULL,
                    TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes - 'update'),
                    _parent_job_id
                    );

            RETURN NEW; -- RETURN
        end if;
    end if;
    UPDATE provision_domain_update SET
        job_id = job_submit(
                v_domain.tenant_customer_id,
                'provision_domain_update',
                NEW.id,
                TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes)
                 ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


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
