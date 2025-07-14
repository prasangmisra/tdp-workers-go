---- create get_tld_setting ----


-- function: get_tld_setting
-- description: Retrieves the value of TLD setting based on provided key and either TLD ID or name, and tenant ID or name.
-- The function parameters have the following precedence:
-- 1. p_tld_id: If provided, this takes precedence over p_tld_name.
-- 2. p_tld_name: Used if p_tld_id is not provided.
-- 3. p_tenant_id: Used with tld id/name. If provided, this takes precedence over p_tenant_name.
-- 4. p_tenant_name: Used if p_tenant_id is not provided.
-- 5. p_accreditation_tld_id: Used if none of the above is provided.
CREATE OR REPLACE FUNCTION get_tld_setting(
    p_key TEXT,
    p_accreditation_tld_id UUID DEFAULT NULL,
    p_tld_id UUID DEFAULT NULL,
    p_tld_name TEXT DEFAULT NULL,
    p_tenant_id UUID DEFAULT NULL,
    p_tenant_name TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    _tld_setting    TEXT;
    v_tld_id        UUID;
    v_tenant_id     UUID;
BEGIN
    -- Determine the TLD ID
    IF p_tld_id IS NOT NULL AND v_tld_id IS NULL THEN
        v_tld_id := p_tld_id;
    ELSIF p_tld_name IS NOT NULL AND v_tld_id IS NULL THEN
        SELECT tld_id INTO v_tld_id FROM v_accreditation_tld WHERE tld_name = p_tld_name;
        IF v_tld_id IS NULL THEN
            RAISE NOTICE 'No TLD found for name %', p_tld_name;
            RETURN NULL;
        END IF;
    ELSEIF p_accreditation_tld_id IS NULL THEN
        RAISE NOTICE 'At least one of the following must be provided: TLD ID/name or accreditation_tld ID';
        RETURN NULL;
    END IF;

    -- Determine the Tenant ID
    IF p_tenant_id IS NOT NULL THEN
        v_tenant_id := p_tenant_id;
    ELSIF p_tenant_name IS NOT NULL THEN
        SELECT tenant_id INTO v_tenant_id FROM v_tenant_customer WHERE tenant_name = p_tenant_name;
        IF v_tenant_id IS NULL THEN
            RAISE NOTICE 'No tenant found for name %', p_tenant_name;
            RETURN NULL;
        END IF;
    END IF;

    -- Determine the TLD ID/Tenant ID from accreditation tld id
    IF p_accreditation_tld_id IS NOT NULL AND v_tld_id IS NULL AND v_tenant_id IS NULL THEN
        SELECT
            tld_id,
            tenant_id
        INTO v_tld_id, v_tenant_id
        FROM v_accreditation_tld
        WHERE accreditation_tld_id = p_accreditation_tld_id;
    END IF;

    -- Retrieve the setting value from the v_attribute
    IF v_tenant_id IS NOT NULL THEN
        SELECT value INTO _tld_setting
        FROM v_attribute va
        WHERE (va.key = p_key OR va.key LIKE '%.' || p_key)
          AND va.tld_id = v_tld_id
          AND va.tenant_id = v_tenant_id;
    ELSE
        SELECT value INTO _tld_setting
        FROM v_attribute va
        WHERE (va.key = p_key OR va.key LIKE '%.' || p_key)
          AND va.tld_id = v_tld_id;
    END IF;

    -- Check if a setting was found
    IF _tld_setting IS NULL THEN
        RAISE NOTICE 'No setting found for key %, TLD ID %, and tenant ID %', p_key, v_tld_id, v_tenant_id;
        RETURN NULL;
    ELSE
        RETURN _tld_setting;
    END IF;
END;
$$ LANGUAGE plpgsql;

---- update existing flows ----
-- contact --

-- function: plan_update_contact_provision()
-- description: update a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_contact_provision() RETURNS TRIGGER AS $$
DECLARE
    v_update_contact    RECORD;
    v_pcu_id            UUID;
    _contact            RECORD;
BEGIN
    -- order information
    SELECT * INTO v_update_contact
    FROM v_order_update_contact
    WHERE order_item_id = NEW.order_item_id;

    FOR _contact IN
    SELECT dc.handle,
           tc_name_from_id('domain_contact_type',dc.domain_contact_type_id) AS type,
           vat.accreditation_id,
           get_tld_setting(
               p_key=>'tld.contact.registrant_contact_update_restricted_fields',
               p_tld_id=>vat.tld_id,
               p_tenant_id=>vtc.tenant_id
           )::TEXT[] AS registrant_contact_update_restricted_fields,
           get_tld_setting(
               p_key=>'tld.contact.is_contact_update_supported',
               p_tld_id=>vat.tld_id,
               p_tenant_id=>vtc.tenant_id
           )::BOOL AS is_contact_update_supported
    FROM domain_contact dc
    JOIN domain d ON d.id = dc.domain_id
    JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    WHERE dc.contact_id = v_update_contact.contact_id
    LOOP
        IF v_pcu_id IS NULL THEN
            WITH pcu_ins AS (
                INSERT INTO provision_contact_update (
                        tenant_customer_id,
                        order_metadata,
                        contact_id,
                        order_contact_id,
                        order_item_plan_ids
                    ) VALUES (
                        v_update_contact.tenant_customer_id,
                        v_update_contact.order_metadata,
                        v_update_contact.contact_id,
                        v_update_contact.order_contact_id,
                        ARRAY [NEW.id]
                    ) RETURNING id
            )
            SELECT id INTO v_pcu_id FROM pcu_ins;
        END IF;
        IF (_contact.type = 'registrant' AND
            check_contact_field_changed_in_order_contact(
                    v_update_contact.order_contact_id,
                    v_update_contact.contact_id,
                    _contact.registrant_contact_update_restricted_fields
                )
            )
               OR NOT _contact.is_contact_update_supported THEN
            IF v_update_contact.reuse_behavior = 'fail' THEN
                -- raise exception to rollback inserted provision
                RAISE EXCEPTION 'contact update not supported';
                -- END LOOP
                EXIT;
            ELSE
                -- insert into provision_domain_contact_update with failed status
                INSERT INTO provision_domain_contact_update(
                    tenant_customer_id,
                    contact_id,
                    order_contact_id,
                    accreditation_id,
                    handle,
                    status_id,
                    provision_contact_update_id
                ) VALUES (
                    v_update_contact.tenant_customer_id,
                    v_update_contact.contact_id,
                    v_update_contact.order_contact_id,
                    _contact.accreditation_id,
                    _contact.handle,
                    tc_id_from_name('provision_status','failed'),
                    v_pcu_id
                 ) ON CONFLICT (provision_contact_update_id, handle) DO UPDATE
                    SET status_id = tc_id_from_name('provision_status','failed');
            END IF;
        ELSE
            -- insert into provision_domain_contact_update with normal flow
            INSERT INTO provision_domain_contact_update(
                tenant_customer_id,
                contact_id,
                order_contact_id,
                accreditation_id,
                handle,
                provision_contact_update_id
            ) VALUES (
                v_update_contact.tenant_customer_id,
                v_update_contact.contact_id,
                v_update_contact.order_contact_id,
                _contact.accreditation_id,
                _contact.handle,
                v_pcu_id
             ) ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    -- No domains linked to this contact, update contact and mark as done.
    IF NOT FOUND THEN
        -- update contact
        PERFORM update_contact_using_order_contact(v_update_contact.contact_id, v_update_contact.order_contact_id);

        -- complete the order item
        UPDATE update_contact_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

        RETURN NEW;
    END IF;

    -- start the flow
    UPDATE provision_contact_update SET is_complete = TRUE WHERE id = v_pcu_id;
    RETURN NEW;

EXCEPTION
    WHEN OTHERS THEN
        -- fail plan
        UPDATE update_contact_plan
        SET status_id = tc_id_from_name('order_item_plan_status','failed')
        WHERE id = NEW.id;

        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- domain -- 

-- function: domain_rgp_status_set_expiry_date()
-- description: sets rgp expiry date according to rgp status and tld grace period configuration
CREATE OR REPLACE FUNCTION domain_rgp_status_set_expiry_date() RETURNS TRIGGER AS $$
DECLARE
  v_period_days  INTEGER;
BEGIN

  IF NEW.expiry_date IS NULL THEN

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.' || rs.name,
        p_tld_name=>vat.tld_name
    ) INTO v_period_days
    FROM domain d
    JOIN rgp_status rs ON rs.id = NEW.status_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    WHERE d.id = NEW.domain_id;

    NEW.expiry_date = NOW() + (v_period_days || 'days')::INTERVAL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: plan_create_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain         RECORD;
    _contact_exists         BOOLEAN;
    _contact_provisioned    BOOLEAN;
    _thin_registry          BOOLEAN;
BEGIN
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    SELECT TRUE INTO _contact_exists
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.is_thin_registry',
        p_tld_id=>vat.tld_id,
        p_tenant_id=>vtc.tenant_id
    ) INTO _thin_registry
    FROM v_tenant_customer vtc
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_create_domain.accreditation_tld_id
    WHERE vtc.id = v_create_domain.tenant_customer_id;

    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
    AND pc.accreditation_id = v_create_domain.accreditation_id;

    IF FOUND OR _thin_registry THEN
        -- contact has already been provisioned, we can mark this as complete.
        UPDATE create_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;
    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids,
            order_metadata
        ) VALUES(
            NEW.reference_id,
            v_create_domain.accreditation_id,
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
    v_dc_host                                   RECORD;
    v_create_domain                             RECORD;
    v_host_object_supported                     BOOLEAN;
    v_host_parent_domain                        RECORD;
    v_host_accreditation                        RECORD;
    v_host_addrs                                INET[];
    v_host_addrs_empty                          BOOLEAN;
BEGIN
    -- Fetch domain creation host details
    SELECT cdn.*,oh."name",oh.tenant_customer_id,oh.domain_id
    INTO v_dc_host
    FROM create_domain_nameserver cdn
             JOIN order_host oh ON oh.id=cdn.host_id
    WHERE
        cdn.id = NEW.reference_id;

    IF v_dc_host.id IS NULL THEN
        RAISE EXCEPTION 'reference id % not found in create_domain_nameserver table', NEW.reference_id;
    END IF;

    -- Load the order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    -- Host provisioning will be skipped if the host object is not supported for domain accreditation.
    SELECT va.value INTO v_host_object_supported
    FROM v_attribute va
    WHERE va.key = 'tld.order.host_object_supported'
      AND va.tld_id = v_create_domain.tld_id;

    -- get value of host_object_supported	flag
    SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_tld_id=>v_create_domain.tld_id
    )
    INTO v_host_object_supported;

    IF v_host_object_supported IS FALSE THEN
        UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
        RETURN NEW;
    END IF;

    -- Host Accreditation
    v_host_accreditation := get_accreditation_tld_by_name(v_dc_host.name, v_dc_host.tenant_customer_id);

    IF v_host_accreditation IS NULL OR v_host_accreditation.accreditation_id IS NULL THEN
        RAISE EXCEPTION 'Hostname ''%'' is invalid', v_dc_host.name;
    END IF;

    -- Check if there are addrs or not
    v_host_addrs := get_order_host_addrs(v_dc_host.host_id);
    v_host_addrs_empty := array_length(v_host_addrs, 1) = 1 AND v_host_addrs[1] IS NULL;

    -- Host parent domain
    v_host_parent_domain := get_host_parent_domain(v_dc_host);

    IF v_create_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
        -- Host and domain are under same accreditation
        IF is_host_provisioned(v_create_domain.accreditation_id, v_dc_host.name) THEN
            -- host already provisioned complete the plan
            UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
            RETURN NEW;
        END IF;

        IF v_host_parent_domain.id IS NULL THEN
            -- customer does not own parent domain
            RAISE EXCEPTION 'Host create not allowed';
        ELSIF v_host_addrs_empty THEN
            -- ip addresses are required to provision host under parent tld
            RAISE EXCEPTION 'Missing IP addresses for hostname';
        END IF;

        PERFORM provision_host(
                v_create_domain.accreditation_id,
                v_create_domain.tenant_customer_id,
                NEW.id,
                v_create_domain.order_metadata,
                v_dc_host.host_id
                );
    ELSE
        -- Host and domain are under different accreditations (registries)
        IF is_host_provisioned(v_create_domain.accreditation_id, v_dc_host.name) THEN
            -- nothing to do; mark plan as completed
            UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
            RETURN NEW;
        END IF;

        PERFORM provision_host(
                v_create_domain.accreditation_id,
                v_create_domain.tenant_customer_id,
                NEW.id,
                v_create_domain.order_metadata,
                v_dc_host.host_id
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
            UPDATE create_domain_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
END;
$$ LANGUAGE plpgsql;

-- function: order_prevent_if_delete_unsupported()
-- description: prevents domain delete if tld not support delete domains
CREATE OR REPLACE FUNCTION order_prevent_if_delete_unsupported() RETURNS TRIGGER AS $$
DECLARE
  v_explicit_delete_supported  BOOLEAN;
BEGIN

  SELECT get_tld_setting(
    p_key=>'tld.lifecycle.explicit_delete_supported',
    p_tld_id=>vat.tld_id
  )
  INTO v_explicit_delete_supported
  FROM domain d
  JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
  WHERE d.name = NEW.name;


  IF NOT v_explicit_delete_supported THEN
      RAISE EXCEPTION 'Explicit domain delete is not allowed';
  END IF;

  RETURN NEW;

END;
$$ LANGUAGE plpgsql;

-- function: order_prevent_if_renew_unsupported()
-- description: prevents domain renew if tld not support renew domains
CREATE OR REPLACE FUNCTION order_prevent_if_renew_unsupported() RETURNS TRIGGER AS $$
DECLARE
  v_explicit_renew_supported  BOOLEAN;
  v_allowed_renew_periods      INT[];
BEGIN

  SELECT get_tld_setting(
    p_key=>'tld.lifecycle.explicit_renew_supported',
    p_tld_id=>vat.tld_id
  )
  INTO v_explicit_renew_supported
  FROM domain d
  JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
  WHERE d.name = NEW.name;

  IF NOT v_explicit_renew_supported THEN
      RAISE EXCEPTION 'Explicit domain renew is not allowed';
  END IF;

  SELECT get_tld_setting(
    p_key=>'tld.lifecycle.allowed_renew_periods',
    p_tld_id=>vat.tld_id
  )
  INTO v_allowed_renew_periods
  FROM domain d
  JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
  WHERE d.name = NEW.name;

  IF NOT (NEW.period = ANY(v_allowed_renew_periods)) THEN
      RAISE EXCEPTION 'Period ''%'' is invalid renew period', NEW.period;
  END IF;

  RETURN NEW;

END;
$$ LANGUAGE plpgsql;

-- function: plan_update_domain_provision_contact()
-- description: create a contact based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain         RECORD;
    _contact_exists         BOOLEAN;
    _contact_provisioned    BOOLEAN;
    _thin_registry          BOOLEAN;
BEGIN
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    SELECT TRUE INTO _contact_exists
    FROM ONLY contact
    WHERE id = NEW.reference_id;

    IF NOT FOUND THEN
        INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
        INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);
        INSERT INTO contact_attribute (SELECT * FROM contact_attribute WHERE contact_id=NEW.reference_id);
    END IF;

    SELECT get_tld_setting(
        p_key=>'tld.lifecycle.is_thin_registry',
        p_tld_id=>vat.tld_id,
        p_tenant_id=>vtc.tenant_id
    )
    INTO _thin_registry
    FROM v_tenant_customer vtc
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_update_domain.accreditation_tld_id
    WHERE vtc.id = v_update_domain.tenant_customer_id;

    SELECT TRUE INTO _contact_provisioned
    FROM provision_contact pc
    WHERE pc.contact_id = NEW.reference_id
    AND pc.accreditation_id = v_update_domain.accreditation_id;

    IF FOUND OR _thin_registry THEN
        -- contact has already been provisioned, we can mark this as complete.
        UPDATE update_domain_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;
    ELSE
        INSERT INTO provision_contact(
            contact_id,
            accreditation_id,
            tenant_customer_id,
            order_item_plan_ids
        ) VALUES(
            NEW.reference_id,
            v_update_domain.accreditation_id,
            v_update_domain.tenant_customer_id,
            ARRAY[NEW.id]
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: order_prevent_if_nameservers_count_is_invalid()
-- description: Check if nameservers count match TLD settings
CREATE OR REPLACE FUNCTION order_prevent_if_nameservers_count_is_invalid() RETURNS TRIGGER AS $$
DECLARE
    v_domain        RECORD;
    _min_ns_attr    INT;
    _max_ns_attr    INT;
    _hosts_count    INT;
BEGIN
    SELECT * INTO v_domain
    FROM domain d
    JOIN "order" o ON o.id=NEW.order_id
    WHERE d.name=NEW.name
      AND d.tenant_customer_id=o.tenant_customer_id;

    SELECT get_tld_setting(
        p_key=>'tld.dns.min_nameservers',
        p_tld_id=>vat.tld_id
    )
    INTO _min_ns_attr
    FROM v_accreditation_tld vat
    WHERE vat.accreditation_tld_id = v_domain.accreditation_tld_id;

    SELECT get_tld_setting(
        p_key=>'tld.dns.max_nameservers',
        p_tld_id=>vat.tld_id
    )
    INTO _max_ns_attr
    FROM v_accreditation_tld vat
    WHERE vat.accreditation_tld_id = v_domain.accreditation_tld_id;

    SELECT CARDINALITY(NEW.hosts) INTO _hosts_count;

    IF _hosts_count < _min_ns_attr OR _hosts_count > _max_ns_attr THEN
        RAISE EXCEPTION 'Nameserver count must be in this range %-%', _min_ns_attr,_max_ns_attr;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- host --

-- function: check_if_tld_supports_host_object()
-- description: checks if tld supports host object or not
CREATE OR REPLACE FUNCTION check_if_tld_supports_host_object(order_type TEXT, order_host_id UUID) RETURNS VOID AS $$
DECLARE
    v_host_object_supported  BOOLEAN;
BEGIN
    SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_tld_id=>vat.tld_id,
        p_tenant_id=>vtc.tenant_id
    )
    INTO v_host_object_supported
    FROM order_host oh
    JOIN domain d ON d.id = oh.domain_id
    JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
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
