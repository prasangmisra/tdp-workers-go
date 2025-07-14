INSERT INTO order_item_strategy(order_type_id, object_id, is_validation_required, provision_order)
VALUES (
    (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update'),
    tc_id_from_name('order_item_object','host'),
    TRUE,
    1
) ON CONFLICT DO NOTHING;

-- function: validate_create_domain_host_plan()
-- description: validates plan items for host provisioning
CREATE OR REPLACE FUNCTION validate_create_domain_host_plan() RETURNS TRIGGER AS $$
DECLARE
    v_dc_host                   RECORD;
    v_create_domain             RECORD;
    v_host_object_supported     BOOLEAN;
    v_job_data                  JSONB;
    v_job_id                    UUID;
BEGIN
    -- Fetch domain creation host details
    SELECT cdn.*, oh."name", oh.tenant_customer_id, oh.domain_id
    INTO v_dc_host
    FROM create_domain_nameserver cdn
    JOIN order_host oh ON oh.id=cdn.host_id
    WHERE cdn.id = NEW.reference_id;

    IF v_dc_host.id IS NULL THEN
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
        p_tld_id=>v_create_domain.tld_id
    )
    INTO v_host_object_supported;

    -- Host provisioning will be skipped if the host object is not supported for domain accreditation.
    IF v_host_object_supported IS FALSE THEN
        UPDATE create_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed'),
                validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;
        
        RETURN NEW;
    END IF;

    v_job_data := jsonb_build_object(
        'host_name', v_dc_host.name,
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

-- function: validate_update_domain_host_plan()
-- description: validates plan items for host provisioning
CREATE OR REPLACE FUNCTION validate_update_domain_host_plan() RETURNS TRIGGER AS $$
DECLARE
    v_du_host                   RECORD;
    v_update_domain             RECORD;
    v_host_object_supported     BOOLEAN;
    v_job_data                  JSONB;
    v_job_id                    UUID;
BEGIN
    -- Fetch domain update host details
    SELECT udan.*, oh."name", oh.tenant_customer_id, oh.domain_id
    INTO v_du_host
    FROM update_domain_add_nameserver udan
    JOIN order_host oh ON oh.id=udan.host_id
    WHERE udan.id = NEW.reference_id;

    IF v_du_host.id IS NULL THEN
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
        p_tld_id=>v_update_domain.tld_id
    )
    INTO v_host_object_supported;

    -- Host provisioning will be skipped if the host object is not supported for domain accreditation.
    IF v_host_object_supported IS FALSE THEN
        UPDATE update_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status', 'completed'),
                validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'completed')
        WHERE id = NEW.id;
        
        RETURN NEW;
    END IF;

    v_job_data := jsonb_build_object(
        'host_name', v_du_host.name,
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

-- function: plan_create_domain_provision_host()
-- description: create a host based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_host() RETURNS TRIGGER AS $$
DECLARE
    v_dc_host                   RECORD;
    v_create_domain             RECORD;
    v_host_accreditation        RECORD;
    v_host_parent_domain        RECORD;
BEGIN
    -- Fetch domain creation host details
    SELECT cdn.*,oh."name",oh.tenant_customer_id,oh.domain_id
    INTO v_dc_host
    FROM create_domain_nameserver cdn
        JOIN order_host oh ON oh.id=cdn.host_id
    WHERE
        cdn.id = NEW.reference_id;

    -- Load the order information
    SELECT * INTO v_create_domain
    FROM v_order_create_domain
    WHERE order_item_id = NEW.order_item_id;

    -- Host Accreditation
    v_host_accreditation := get_accreditation_tld_by_name(v_dc_host.name, v_dc_host.tenant_customer_id);
    IF v_host_accreditation IS NOT NULL THEN
        IF v_create_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
            -- Host and domain are under same accreditation, run additional checks

            v_host_parent_domain := get_host_parent_domain(v_dc_host.name,v_dc_host.tenant_customer_id);

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

    -- Provision the host
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

-- function: plan_update_domain_provision_host()
-- description: create a host based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_host() RETURNS TRIGGER AS $$
DECLARE
    v_du_host                   RECORD;
    v_update_domain             RECORD;
    v_host_accreditation        RECORD;
    v_host_parent_domain        RECORD;
BEGIN
    -- Fetch domain update host details
    SELECT udan.*, oh."name", oh.tenant_customer_id, oh.domain_id
    INTO v_du_host
    FROM update_domain_add_nameserver udan
        JOIN order_host oh ON oh.id=udan.host_id
    WHERE
        udan.id = NEW.reference_id;

    -- Load the order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- Host Accreditation
    v_host_accreditation := get_accreditation_tld_by_name(v_du_host.name, v_du_host.tenant_customer_id);
    IF v_host_accreditation IS NOT NULL THEN
        IF v_update_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
            -- Host and domain are under same accreditation, run additional checks

            v_host_parent_domain := get_host_parent_domain(v_du_host.name, v_du_host.tenant_customer_id);

            IF v_host_parent_domain is NULL THEN
                RAISE EXCEPTION 'Parent domain not found';
            END IF;

            IF v_host_parent_domain.name = v_du_host.name THEN
                RAISE EXCEPTION 'Host names such as % that could be confused with a domain name cannot be accepted', v_dc_host.name;
            END IF;

            -- Check if there are addrs or not
            IF get_order_host_addrs(v_du_host.host_id) = '{}'::INET[] THEN
                -- ip addresses are required to provision host under parent tld
                RAISE EXCEPTION 'Missing IP addresses for hostname';
            END IF;
        END IF;
    END IF;

    -- Provision the host
    INSERT INTO provision_host(
        accreditation_id,
        host_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids
    ) VALUES (
        v_update_domain.accreditation_id,
        v_du_host.host_id,
        v_update_domain.tenant_customer_id,
        v_update_domain.order_metadata,
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
            UPDATE update_domain_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
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
            order_item_plan_ids,
            order_metadata
        ) VALUES(
            NEW.reference_id,
            v_update_domain.accreditation_id,
            v_update_domain.tenant_customer_id,
            ARRAY[NEW.id],
            v_update_domain.order_metadata
        );
    END IF;
    RETURN NEW;
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

DROP TRIGGER IF EXISTS order_prevent_if_nameserver_does_not_exist_tg ON order_item_update_domain;
DROP TRIGGER IF EXISTS order_prevent_if_nameservers_count_is_invalid_tg ON order_item_update_domain;

DROP FUNCTION IF EXISTS order_prevent_if_nameserver_does_not_exist;
DROP FUNCTION IF EXISTS order_prevent_if_nameservers_count_is_invalid;

--
-- table: update_domain_add_nameserver
-- description: this table stores attributes of host to be added to domain.
--

CREATE TABLE IF NOT EXISTS update_domain_add_nameserver (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  update_domain_id   UUID NOT NULL REFERENCES order_item_update_domain,
  host_id            UUID NOT NULL REFERENCES order_host  
) INHERITS(class.audit);

CREATE INDEX IF NOT EXISTS update_domain_add_nameserver_update_domain_id_idx ON update_domain_add_nameserver(update_domain_id);
CREATE INDEX IF NOT EXISTS update_domain_add_nameserver_host_id_idx ON update_domain_add_nameserver(host_id);

--
-- table: update_domain_rem_nameserver
-- description: this table stores attributes of host to be removed from domain.
--

CREATE TABLE IF NOT EXISTS update_domain_rem_nameserver (
  id                 UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  update_domain_id   UUID NOT NULL REFERENCES order_item_update_domain,
  host_id            UUID NOT NULL REFERENCES order_host  
) INHERITS(class.audit);

CREATE INDEX IF NOT EXISTS update_domain_rem_nameserver_update_domain_id_idx ON update_domain_rem_nameserver(update_domain_id);
CREATE INDEX IF NOT EXISTS update_domain_rem_nameserver_host_id_idx ON update_domain_rem_nameserver(host_id);

CREATE INDEX IF NOT EXISTS update_domain_add_secdns_update_domain_id_idx ON update_domain_add_secdns(update_domain_id);
CREATE INDEX IF NOT EXISTS update_domain_rem_secdns_update_domain_id_idx ON update_domain_rem_secdns(update_domain_id);

DROP TRIGGER IF EXISTS validate_update_domain_host_plan_tg ON update_domain_plan;
CREATE TRIGGER validate_update_domain_host_plan_tg
    AFTER UPDATE ON update_domain_plan
    FOR EACH ROW WHEN (
      OLD.validation_status_id <> NEW.validation_status_id
      AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host')
    )
    EXECUTE PROCEDURE validate_update_domain_host_plan();

DROP TRIGGER IF EXISTS plan_update_domain_provision_host_tg ON update_domain_plan;
CREATE TRIGGER plan_update_domain_provision_host_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host') 
  )
  EXECUTE PROCEDURE plan_update_domain_provision_host();

DROP TRIGGER IF EXISTS plan_update_domain_provision_host_skipped_tg ON update_domain_plan;
CREATE TRIGGER plan_update_domain_provision_host_skipped_tg 
  AFTER UPDATE ON update_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id = tc_id_from_name('order_item_plan_status','new')
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','completed')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host') 
  )
  EXECUTE PROCEDURE provision_domain_host_skipped();


CREATE OR REPLACE VIEW v_order_item_plan_object AS 
SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_contact.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM create_domain_contact
    WHERE create_domain_id = d.id
  ) AS distinct_order_contact ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_host.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
  JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM create_domain_nameserver
    WHERE create_domain_id = d.id
  ) AS distinct_order_host ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_renew_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id AS object_id,
  d.id AS id
FROM order_item_redeem_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj on obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_delete_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_transfer_in_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_transfer_away_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_host.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
  JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM update_domain_add_nameserver
    WHERE update_domain_id = d.id
  ) AS distinct_order_host ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_contact.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM update_domain_contact
    WHERE update_domain_id = d.id
  ) AS distinct_order_contact ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting_certificate'

UNION


SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_delete_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_update_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_create_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_update_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_delete_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_update_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
;

DROP VIEW IF EXISTS v_order_update_domain;
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
    ud.auto_renew,
    ud.locks,
    ud.secdns_max_sig_life
FROM order_item_update_domain ud
     JOIN "order" o ON o.id=ud.order_id
     JOIN v_order_type ot ON ot.id = o.type_id
     JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
     JOIN order_status s ON s.id = o.status_id
     JOIN v_accreditation_tld at ON at.accreditation_tld_id = ud.accreditation_tld_id
     JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=ud.name
;

ALTER TABLE order_item_update_domain DROP COLUMN IF EXISTS hosts;

-- function: provision_domain_update_job()
-- description: creates the job to update the domain.
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
                                       'accreditation',v_domain.accreditation),
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

-- function: provision_host_job()
-- description: creates the job to create the host
CREATE OR REPLACE FUNCTION provision_host_job() RETURNS TRIGGER AS $$
DECLARE
    v_host     RECORD;
BEGIN
    SELECT
        NEW.id AS provision_host_id,
        NEW.tenant_customer_id AS tenant_customer_id,
        jsonb_get_host_by_id(oh.id) AS host,
        TO_JSONB(va.*) AS accreditation,
        get_accreditation_tld_by_name(oh.name, oh.tenant_customer_id) AS host_accreditation_tld,
        FALSE AS host_ip_required_non_auth, -- should come from registry settings
        NEW.order_metadata AS metadata
    INTO v_host
    FROM order_host oh
        JOIN v_accreditation va ON va.accreditation_id = NEW.accreditation_id
    WHERE oh.id=NEW.host_id;

    UPDATE provision_host SET job_id=job_submit(
        NEW.tenant_customer_id,
        'provision_host_create',
        NEW.id,
        TO_JSONB(v_host.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


ALTER TABLE provision_domain_update DROP COLUMN IF EXISTS hosts;

--
-- table: provision_domain_update_add_host
-- description: this table is to add a domain nameserver association in a backend.
--

CREATE TABLE IF NOT EXISTS provision_domain_update_add_host (
  id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id  UUID NOT NULL REFERENCES provision_domain_update 
                              ON DELETE CASCADE,
  host_id                     UUID NOT NULL REFERENCES host
) INHERITS(class.audit_trail);

--
-- table: provision_domain_update_rem_host
-- description: this table is to remove a domain nameserver association in a backend.
--

CREATE TABLE IF NOT EXISTS provision_domain_update_rem_host (
  id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id  UUID NOT NULL REFERENCES provision_domain_update 
                              ON DELETE CASCADE,
  host_id                     UUID NOT NULL REFERENCES host
) INHERITS(class.audit_trail);

DROP TRIGGER provision_host_success_tg ON provision_host;
CREATE TRIGGER provision_host_success_tg
  BEFORE UPDATE ON provision_host
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_host_success();


-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
DECLARE
    _key   text;
    _value BOOLEAN;
BEGIN

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            NEW.domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_update_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
        DO UPDATE SET contact_id = EXCLUDED.contact_id, handle = EXCLUDED.handle;


    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            NEW.domain_id,
            h.id
        FROM provision_domain_update_add_host pduah
            JOIN ONLY host h ON h.id = pduah.host_id
        WHERE pduah.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete association for removed hosts
    WITH removed_hosts AS (
        SELECT h.*
        FROM provision_domain_update_rem_host pdurh
            JOIN ONLY host h ON h.id = pdurh.host_id
        WHERE pdurh.provision_domain_update_id = NEW.id
    )
    DELETE FROM
        domain_host dh
    WHERE dh.domain_id = NEW.domain_id
        AND dh.host_id IN (SELECT id FROM removed_hosts);

    -- update auto renew flag if changed
    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew),
        auth_info = COALESCE(NEW.auth_info, d.auth_info),
        secdns_max_sig_life = COALESCE(NEW.secdns_max_sig_life, d.secdns_max_sig_life)
    WHERE d.id = NEW.domain_id;

    -- update locks
    IF NEW.locks IS NOT NULL THEN
        FOR _key, _value IN SELECT * FROM jsonb_each_text(NEW.locks)
            LOOP
                IF _value THEN
                    INSERT INTO domain_lock(domain_id,type_id) VALUES
                        (NEW.domain_id,(SELECT id FROM lock_type where name=_key)) ON CONFLICT DO NOTHING ;

                ELSE
                    DELETE FROM domain_lock WHERE domain_id=NEW.domain_id AND
                        type_id=tc_id_from_name('lock_type',_key);
                end if;
            end loop;
    end if;


    -- remove secdns data

    WITH secdns_ds_data_rem AS (
        SELECT 
            secdns.ds_data_id AS id,
            secdns.ds_key_data_id AS key_data_id
        FROM provision_domain_update_rem_secdns pdurs
            JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
            LEFT JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            -- matching existing ds data (including optional ds key data) on domain
            JOIN LATERAL (
                SELECT
                    ds.domain_id,
                    ds.ds_data_id,
                    sdd.key_data_id AS ds_key_data_id
                FROM domain_secdns ds
                    JOIN secdns_ds_data sdd ON sdd.id = ds.ds_data_id
                    LEFT JOIN secdns_key_data skd ON skd.id = sdd.key_data_id
                WHERE ds.domain_id = NEW.domain_id
                    AND sdd.key_tag = osdd.key_tag
                    AND sdd.algorithm = osdd.algorithm
                    AND sdd.digest_type = osdd.digest_type
                    AND sdd.digest = osdd.digest
                    AND (
                        (sdd.key_data_id IS NULL AND osdd.key_data_id IS NULL)
                        OR
                        (
                            skd.flags = oskd.flags
                            AND skd.protocol = oskd.protocol
                            AND skd.algorithm = oskd.algorithm
                            AND skd.public_key = oskd.public_key
                        )
                    )
            ) secdns ON TRUE
        WHERE pdurs.provision_domain_update_id = NEW.id
    ),
    -- remove ds key data first if exists
    secdns_ds_key_data_rem AS (
        DELETE FROM ONLY secdns_key_data WHERE id IN (
            SELECT key_data_id FROM secdns_ds_data_rem WHERE key_data_id IS NOT NULL
        )
    )
    -- remove ds data if any
    DELETE FROM ONLY secdns_ds_data WHERE id IN (SELECT id FROM secdns_ds_data_rem);

    WITH secdns_key_data_rem AS (
        SELECT 
            secdns.key_data_id AS id
        FROM provision_domain_update_rem_secdns pdurs
            JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            JOIN order_secdns_key_data oskd ON oskd.id = udrs.key_data_id
            -- matching existing key data on domain
            JOIN LATERAL (
                SELECT
                    domain_id,
                    key_data_id
                FROM domain_secdns ds
                    JOIN secdns_key_data skd ON skd.id = ds.key_data_id
                WHERE ds.domain_id = NEW.domain_id
                    AND skd.flags = oskd.flags
                    AND skd.protocol = oskd.protocol
                    AND skd.algorithm = oskd.algorithm
                    AND skd.public_key = oskd.public_key
            ) secdns ON TRUE
        WHERE pdurs.provision_domain_update_id = NEW.id
    )
    -- remove key data if any
    DELETE FROM ONLY secdns_key_data WHERE id IN (SELECT id FROM secdns_key_data_rem);

    -- add secdns data

    WITH key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_key_data oskd ON oskd.id = udas.key_data_id
            WHERE pduas.provision_domain_update_id = NEW.id
        ) RETURNING id
    ), ds_key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            WHERE pduas.provision_domain_update_id = NEW.id
        ) RETURNING id
    ), ds_data AS (
        INSERT INTO secdns_ds_data
        (
            SELECT 
                osdd.id,
                osdd.key_tag,
                osdd.algorithm,
                osdd.digest_type,
                osdd.digest,
                dkd.id AS key_data_id
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                LEFT JOIN ds_key_data dkd ON dkd.id = osdd.key_data_Id
            WHERE pduas.provision_domain_update_id = NEW.id
        ) RETURNING id
    )
    INSERT INTO domain_secdns (
        domain_id,
        ds_data_id,
        key_data_id
    )(
        SELECT NEW.domain_id, NULL, id FROM key_data
        
        UNION ALL
        
        SELECT NEW.domain_id, id, NULL FROM ds_data
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
