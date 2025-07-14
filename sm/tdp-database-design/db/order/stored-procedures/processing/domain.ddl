-- function: plan_create_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain             RECORD;
    v_create_domain_contact     RECORD;
    _thin_registry              BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    SELECT * INTO v_create_domain_contact
    FROM create_domain_contact
    WHERE order_contact_id = NEW.reference_id
      AND create_domain_id = NEW.order_item_id;

    PERFORM TRUE
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    -- Check if the registry is thin
    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.is_thin_registry', 
        p_accreditation_tld_id => v_create_domain.accreditation_tld_id
    ) INTO _thin_registry;

    -- Check if contact is already provisioned
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_create_domain.accreditation_id;

    -- Check if at least one contact type specified for this contact is supported
    SELECT BOOL_OR(is_contact_type_supported_for_tld(
            v_create_domain_contact.domain_contact_type_id,
        v_create_domain.accreditation_tld_id
    )) INTO _supported_contact_type;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN
        
        UPDATE create_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            accreditation_tld_id,
            domain_contact_type_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
            NEW.reference_id,
            v_create_domain.accreditation_id,
            v_create_domain.accreditation_tld_id,
            v_create_domain_contact.domain_contact_type_id,
            v_create_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_create_domain.order_metadata
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_create_domain_provision_host()
-- description: create a host based on the plan
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

            -- If there are IPv6 addresses, check if tld supports IPv6.
            IF NOT is_host_ipv6_supported(v_order_host_addrs, v_create_domain.accreditation_tld_id) THEN
                RAISE EXCEPTION 'IPv6 addresses are not supported by the ''%'' tld', tld_part(v_create_domain.domain_name);
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


-- function: plan_update_domain_provision_host()
-- description: create a host based on the plan
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

            -- If there are IPv6 addresses, check if tld supports IPv6.
            IF NOT is_host_ipv6_supported(v_order_host_addrs, v_update_domain.accreditation_tld_id) THEN
                RAISE EXCEPTION 'IPv6 addresses are not supported by the ''%'' tld', tld_part(v_update_domain.domain_name);
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


-- function: plan_delete_domain_provision()
-- description: deletes a domain based on the plan
CREATE OR REPLACE FUNCTION plan_delete_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_delete_domain RECORD;
    v_pd_id         UUID;
BEGIN
    SELECT * INTO v_delete_domain
    FROM v_order_delete_domain
    WHERE order_item_id = NEW.order_item_id;

    WITH pd_ins AS (
        INSERT INTO provision_domain_delete(
            domain_id,
            domain_name,
            accreditation_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES(
            v_delete_domain.domain_id,
            v_delete_domain.domain_name,
            v_delete_domain.accreditation_id,
            v_delete_domain.tenant_customer_id,
            v_delete_domain.order_metadata,
            ARRAY[NEW.id]
        ) RETURNING id
   ) SELECT id INTO v_pd_id FROM pd_ins;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_create_domain_provision_domain()
-- description: create a domain based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain   RECORD;
    v_pd_id           UUID;
    v_parent_id       UUID;
    v_locks_required_changes jsonb;
    v_order_item_plan_ids UUID[];
BEGIN
    -- order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    WITH pd_ins AS (
        INSERT INTO provision_domain(
            domain_name,
            registration_period,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            auto_renew,
            secdns_max_sig_life,
            uname,
            language,
            pw,
            tags,
            metadata,
            launch_data,
            order_metadata
        ) VALUES(
            v_create_domain.domain_name,
            v_create_domain.registration_period,
            v_create_domain.accreditation_id,
            v_create_domain.accreditation_tld_id,
            v_create_domain.tenant_customer_id,
            v_create_domain.auto_renew,
            v_create_domain.secdns_max_sig_life,
            v_create_domain.uname,
            v_create_domain.language,
            COALESCE(v_create_domain.auth_info, TC_GEN_PASSWORD(16)),
            COALESCE(v_create_domain.tags,ARRAY[]::TEXT[]),
            COALESCE(v_create_domain.metadata, '{}'::JSONB),
            COALESCE(v_create_domain.launch_data, '{}'::JSONB),
            v_create_domain.order_metadata
        ) RETURNING id
    )
    SELECT id INTO v_pd_id FROM pd_ins;

    SELECT
        jsonb_object_agg(key, value)
    INTO v_locks_required_changes FROM jsonb_each(v_create_domain.locks) WHERE value::BOOLEAN = TRUE;

    IF NOT is_jsonb_empty_or_null(v_locks_required_changes) THEN
        WITH inserted_domain_update AS (
            INSERT INTO provision_domain_update(
                domain_name,
                accreditation_id,
                accreditation_tld_id,
                tenant_customer_id,
                order_metadata,
                order_item_plan_ids,
                locks
            ) VALUES (
                v_create_domain.domain_name,
                v_create_domain.accreditation_id,
                v_create_domain.accreditation_tld_id,
                v_create_domain.tenant_customer_id,
                v_create_domain.order_metadata,
                ARRAY[NEW.id],
                v_locks_required_changes
            ) RETURNING id
        )
        SELECT id INTO v_parent_id FROM inserted_domain_update;
    ELSE
        v_order_item_plan_ids := ARRAY [NEW.id];
    END IF;

    -- insert contacts
    INSERT INTO provision_domain_contact(
        provision_domain_id,
        contact_id,
        contact_type_id
    ) (
        SELECT
            v_pd_id,
            order_contact_id,
            domain_contact_type_id
        FROM create_domain_contact
        WHERE create_domain_id = NEW.order_item_id
        AND is_contact_type_supported_for_tld(domain_contact_type_id, v_create_domain.accreditation_tld_id)
    );

    -- insert hosts
    INSERT INTO provision_domain_host(
        provision_domain_id,
        host_id
    ) (
        SELECT
            v_pd_id,
            h.id
        FROM ONLY host h
                 JOIN order_host oh ON oh.name = h.name
                 JOIN create_domain_nameserver cdn ON cdn.host_id = oh.id
        WHERE cdn.create_domain_id = NEW.order_item_id AND oh.tenant_customer_id = h.tenant_customer_id
    );

    -- insert secdns
    INSERT INTO provision_domain_secdns(
        provision_domain_id,
        secdns_id
    ) (
        SELECT
            v_pd_id,
            cds.id 
        FROM create_domain_secdns cds
        WHERE cds.create_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain
    SET is_complete = TRUE, order_item_plan_ids = v_order_item_plan_ids, parent_id = v_parent_id
    WHERE id = v_pd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_renew_domain_provision()
-- description: renews a domain based on the plan
CREATE OR REPLACE FUNCTION plan_renew_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_renew_domain   RECORD;
BEGIN

    -- order information
    SELECT * INTO v_renew_domain
    FROM v_order_renew_domain
    WHERE order_item_id = NEW.order_item_id;

    -- -- we now signal the provisioning
    INSERT INTO provision_domain_renew(
        domain_id,
        domain_name,
        period,
        accreditation_id,
        tenant_customer_id,
        current_expiry_date,
        order_metadata,
        order_item_plan_ids
    ) VALUES(
                v_renew_domain.domain_id,
                v_renew_domain.domain_name,
                v_renew_domain.period,
                v_renew_domain.accreditation_id,
                v_renew_domain.tenant_customer_id,
                v_renew_domain.current_expiry_date,
                v_renew_domain.order_metadata,
                ARRAY[NEW.id]
            );


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_redeem_domain_provision()
-- description: redeem a domain based on the plan
CREATE OR REPLACE FUNCTION plan_redeem_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_redeem_domain RECORD;
BEGIN

    -- order info
    SELECT * INTO v_redeem_domain
    FROM v_order_redeem_domain
    WHERE order_item_id = NEW.order_item_id;

    -- insert into provision table to trigger job creation
    INSERT INTO provision_domain_redeem(
        domain_id,
        domain_name,
        tenant_customer_id,
        accreditation_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES(
                v_redeem_domain.domain_id,
                v_redeem_domain.domain_name,
                v_redeem_domain.tenant_customer_id,
                v_redeem_domain.accreditation_id,
                v_redeem_domain.order_metadata,
                ARRAY[NEW.id]
            );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_update_domain_contact     RECORD;
    _contact_exists             BOOLEAN;
    _contact_provisioned        BOOLEAN;
    _thin_registry              BOOLEAN;
    _supported_contact_type     BOOLEAN;
BEGIN
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;


    SELECT * INTO v_update_domain_contact
    FROM (
        SELECT domain_contact_type_id FROM update_domain_contact
        WHERE order_contact_id = NEW.reference_id
        AND update_domain_id = NEW.order_item_id

        UNION

        SELECT domain_contact_type_id FROM update_domain_add_contact
        WHERE order_contact_id = NEW.reference_id
        AND update_domain_id = NEW.order_item_id
    ) combined_results;

    -- Check if trying to add a contact type that already exists and is not being removed
    IF EXISTS (
        SELECT 1
        FROM update_domain_add_contact udac
        JOIN domain_contact dc ON dc.domain_id = v_update_domain.domain_id
            AND dc.domain_contact_type_id = udac.domain_contact_type_id
        WHERE udac.update_domain_id = NEW.order_item_id
            AND udac.order_contact_id = NEW.reference_id
            -- for registrant can be changed without removing
            AND dc.domain_contact_type_id <> tc_id_from_name('domain_contact_type', 'registrant')
            AND NOT EXISTS (
                SELECT 1 FROM update_domain_rem_contact udrc
                WHERE udrc.update_domain_id = NEW.order_item_id
                    AND udrc.domain_contact_type_id = udac.domain_contact_type_id
            )
    ) THEN
        RAISE EXCEPTION 'Cannot add contact type because it already exists and is not being removed';
    END IF;

    SELECT TRUE INTO _contact_exists
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    -- Check if the registry is thin
    SELECT get_tld_setting(
        p_key=>'tld.lifecycle.is_thin_registry',
        p_accreditation_tld_id=>v_update_domain.accreditation_tld_id)
    INTO _thin_registry;

    -- Check if contact is already provisioned
    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
      AND pc.accreditation_id = v_update_domain.accreditation_id;

    -- Check if at least one contact type specified for this contact is supported
    SELECT BOOL_OR(is_contact_type_supported_for_tld(
        v_update_domain_contact.domain_contact_type_id,
        v_update_domain.accreditation_tld_id
    )) INTO _supported_contact_type;

    -- Skip contact provision if contact is already provisioned, not supported or the registry is thin
    IF _contact_provisioned OR NOT _supported_contact_type OR _thin_registry THEN

        UPDATE update_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            accreditation_tld_id,
            domain_contact_type_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        )
        VALUES (
            NEW.reference_id,
            v_update_domain.accreditation_id,
            v_update_domain.accreditation_tld_id,
            v_update_domain_contact.domain_contact_type_id,
            v_update_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_update_domain.order_metadata
        );
    END IF;

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


-- function: plan_update_domain_provision_domain()
-- description: update a domain based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_pdu_id                     UUID;
BEGIN
    -- order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- we now signal the provisioning
    WITH pdu_ins AS (
        INSERT INTO provision_domain_update(
            domain_id,
            domain_name,
            auth_info,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            auto_renew,
            order_metadata,
            order_item_plan_ids,
            locks,
            secdns_max_sig_life
        ) VALUES(
            v_update_domain.domain_id,
            v_update_domain.domain_name,
            v_update_domain.auth_info,
            v_update_domain.accreditation_id,
            v_update_domain.accreditation_tld_id,
            v_update_domain.tenant_customer_id,
            v_update_domain.auto_renew,
            v_update_domain.order_metadata,
            ARRAY[NEW.id],
            v_update_domain.locks,
            v_update_domain.secdns_max_sig_life
        ) RETURNING id
    )
    SELECT id INTO v_pdu_id FROM pdu_ins;

    -- insert contacts
    INSERT INTO provision_domain_update_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )(
        SELECT
            v_pdu_id,
            order_contact_id,
            domain_contact_type_id
        FROM update_domain_contact
        WHERE update_domain_id = NEW.order_item_id
    );

    INSERT INTO provision_domain_update_add_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )(
        SELECT
            v_pdu_id,
            order_contact_id,
            domain_contact_type_id
        FROM update_domain_add_contact
        WHERE update_domain_id = NEW.order_item_id
    );

    INSERT INTO provision_domain_update_rem_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )(
        SELECT
            v_pdu_id,
            order_contact_id,
            domain_contact_type_id
        FROM update_domain_rem_contact
        WHERE update_domain_id = NEW.order_item_id
    );

    -- insert hosts to add
    INSERT INTO provision_domain_update_add_host(
        provision_domain_update_id,
        host_id
    ) (
        SELECT
            v_pdu_id,
            h.id
        FROM ONLY host h
            JOIN order_host oh ON oh.name = h.name
            JOIN update_domain_add_nameserver udan ON udan.host_id = oh.id
        WHERE udan.update_domain_id = NEW.order_item_id AND oh.tenant_customer_id = h.tenant_customer_id
    );

    -- insert hosts to remove
    INSERT INTO provision_domain_update_rem_host(
        provision_domain_update_id,
        host_id
    ) (
        SELECT
            v_pdu_id,
            h.id
        FROM ONLY host h
            JOIN order_host oh ON oh.name = h.name
            JOIN update_domain_rem_nameserver udrn ON udrn.host_id = oh.id
            JOIN domain_host dh ON dh.host_id = h.id
        WHERE udrn.update_domain_id = NEW.order_item_id 
            AND oh.tenant_customer_id = h.tenant_customer_id
            -- make sure host to be removed is associated with domain
            AND dh.domain_id = v_update_domain.domain_id
    );

    -- insert secdns to add
    INSERT INTO provision_domain_update_add_secdns (
        provision_domain_update_id,
        secdns_id
    )(
        SELECT
            v_pdu_id,
            id
        FROM update_domain_add_secdns
        WHERE update_domain_id = NEW.order_item_id
    );

    -- insert hosts to remove
    INSERT INTO provision_domain_update_rem_secdns (
        provision_domain_update_id,
        secdns_id
    )(
        SELECT
            v_pdu_id,
            id
        FROM update_domain_rem_secdns
        WHERE update_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain_update SET is_complete = TRUE WHERE id = v_pdu_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: plan_transfer_in_domain_provision_domain()
-- description: responsible for creation of transfer in request and finalizing domain transfer
CREATE OR REPLACE FUNCTION plan_transfer_in_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in_domain        RECORD;
    v_provision_domain_transfer_in_request_id       UUID;
BEGIN

    SELECT * INTO v_transfer_in_domain
    FROM v_order_transfer_in_domain
    WHERE order_item_id = NEW.order_item_id;

    IF NEW.provision_order = 1 THEN

        -- first step in transfer_in processing
        -- request will be sent to registry
        INSERT INTO provision_domain_transfer_in_request(
            domain_name,
            pw,
            transfer_period,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES(
            v_transfer_in_domain.domain_name,
            v_transfer_in_domain.auth_info,
            v_transfer_in_domain.transfer_period,
            v_transfer_in_domain.accreditation_id,
            v_transfer_in_domain.accreditation_tld_id,
            v_transfer_in_domain.tenant_customer_id,
            v_transfer_in_domain.order_metadata,
            ARRAY[NEW.id]
        );

    ELSIF NEW.provision_order = 2 THEN

        -- second step in transfer_in processing
        -- check if transfer was approved

        SELECT pdt.id
        INTO v_provision_domain_transfer_in_request_id
        FROM provision_domain_transfer_in_request pdt
        JOIN transfer_in_domain_plan tidp ON tidp.parent_id = NEW.id
        JOIN transfer_status ts ON ts.id = pdt.transfer_status_id
        WHERE tidp.id = ANY(pdt.order_item_plan_ids) AND ts.is_final AND ts.is_success;

        IF NOT FOUND THEN
            UPDATE transfer_in_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status','failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END IF;

        -- fetch data from registry and provision domain entry
        INSERT INTO provision_domain_transfer_in(
            domain_name,
            pw,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            provision_transfer_request_id,
            tags,
            metadata,
            order_metadata,
            order_item_plan_ids
        ) VALUES (
            v_transfer_in_domain.domain_name,
            v_transfer_in_domain.auth_info,
            v_transfer_in_domain.accreditation_id,
            v_transfer_in_domain.accreditation_tld_id,
            v_transfer_in_domain.tenant_customer_id,
            v_provision_domain_transfer_in_request_id,
            v_transfer_in_domain.tags,
            v_transfer_in_domain.metadata,
            v_transfer_in_domain.order_metadata,
            ARRAY[NEW.id]
        );

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_domain_host_skipped()
-- description: inserts host record for already existing hosts
CREATE OR REPLACE FUNCTION provision_domain_host_skipped() RETURNS TRIGGER AS $$
DECLARE
    v_domain_host   RECORD;
BEGIN
    -- Fetch domain host from order data
    WITH domain_ns AS (
        SELECT cdn.host_id FROM create_domain_nameserver cdn WHERE cdn.id = NEW.reference_id
        UNION ALL
        SELECT udan.host_id FROM update_domain_add_nameserver udan WHERE udan.id = NEW.reference_id
    )
    SELECT * INTO v_domain_host FROM domain_ns;

    -- create new host for customer
    INSERT INTO host (SELECT h.* FROM host h WHERE h.id = v_domain_host.host_id)
    ON CONFLICT (tenant_customer_id,name) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_transfer_away_domain_provision()
-- description: responsible for creation of transfer in request and finalizing domain transfer
CREATE OR REPLACE FUNCTION plan_transfer_away_domain_provision() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_away_domain          RECORD;
    _transfer_status_name           TEXT;
    _provision_id                   UUID;
    _transfer_status                RECORD;
BEGIN
    SELECT * INTO v_transfer_away_domain
    FROM v_order_transfer_away_domain
    WHERE order_item_id = NEW.order_item_id;

    SELECT tc_name_from_id('transfer_status', v_transfer_away_domain.transfer_status_id)
    INTO _transfer_status_name;

    IF NEW.provision_order = 1 THEN
        -- fail order if client cancelled
        IF _transfer_status_name = 'clientCancelled' THEN
            UPDATE transfer_away_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status','failed')
            WHERE id = NEW.id;
            RETURN NEW;
        END IF;

        INSERT INTO provision_domain_transfer_away(
            domain_id,
            domain_name,
            pw,
            transfer_status_id,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES(
            v_transfer_away_domain.domain_id,
            v_transfer_away_domain.domain_name,
            v_transfer_away_domain.auth_info,
            v_transfer_away_domain.transfer_status_id,
            v_transfer_away_domain.accreditation_id,
            v_transfer_away_domain.accreditation_tld_id,
            v_transfer_away_domain.tenant_customer_id,
            v_transfer_away_domain.order_metadata,
            ARRAY[NEW.id]
        ) RETURNING id INTO _provision_id;

        IF _transfer_status_name = 'serverApproved' THEN
            UPDATE provision_domain_transfer_away
            SET status_id = tc_id_from_name('provision_status', 'completed')
            WHERE id = _provision_id;
        END IF;
    ELSIF NEW.provision_order = 2 THEN
        SELECT * INTO _transfer_status FROM transfer_status WHERE id = v_transfer_away_domain.transfer_status_id;

        IF _transfer_status.is_success THEN
            -- fail all related order items
            UPDATE order_item_plan
            SET status_id = tc_id_from_name('order_item_plan_status','failed')
            WHERE order_item_id IN (
                SELECT order_item_id
                FROM v_domain_order_item
                WHERE domain_name = v_transfer_away_domain.domain_name
                  AND NOT order_status_is_final
                  AND order_item_id <> NEW.order_item_id
                  AND tenant_customer_id = v_transfer_away_domain.tenant_customer_id
            );

            UPDATE transfer_away_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status','completed')
            WHERE id = NEW.id;
        ELSE
            UPDATE transfer_away_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status','failed')
            WHERE id = NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
