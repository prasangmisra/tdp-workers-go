ALTER TABLE IF EXISTS provision_domain_transfer_in ADD COLUMN IF NOT EXISTS provision_transfer_request_id UUID DEFAULT NULL REFERENCES provision_domain_transfer_in_request;

-- Function to handle domain transfer in request event
CREATE OR REPLACE FUNCTION event_domain_transfer_in_request()
    RETURNS TRIGGER AS
$$
DECLARE
    v_event_header JSONB;
    v_tenant_id    UUID;
    v_payload      JSONB;
    v_is_transfer_success BOOLEAN;
    v_transfer_status TEXT;
BEGIN
    SELECT name,
           is_success
    INTO v_transfer_status,v_is_transfer_success
    FROM transfer_status
    WHERE id = NEW.transfer_status_id;

    -- If the transfer status is success, skip creating an event now;
    -- It will be created after the provision_domain_transfer_in record is finalized.
    IF v_is_transfer_success THEN
        RETURN NEW;
    END IF;

    SELECT tenant_customer.tenant_id
    INTO v_tenant_id
    FROM tenant_customer
    WHERE id = NEW.tenant_customer_id;

    v_event_header = COALESCE(NEW.order_metadata,'{}') || jsonb_build_object('version', '1.0');



    v_payload = build_domain_transfer_payload(
            p_name := NEW.domain_name,
            p_transfer_status := v_transfer_status,
            p_action_by := NEW.action_by,
            p_action_date := NEW.action_date,
            p_requested_by := NEW.tenant_customer_id::TEXT,
            p_requested_date := NEW.requested_date,
            p_expiry_date := NEW.expiry_date
                );

    -- Insert Event for Transfer Away Creation
    PERFORM insert_event(
            p_tenant_id := v_tenant_id,
            p_type_id := tc_id_from_name('event_type', 'domain_transfer'),
            p_payload := v_payload,
            p_header := v_event_header,
            p_reference_id := NEW.id
            );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle domain transfer in event
CREATE OR REPLACE FUNCTION event_domain_transfer_in(p_provision_domain_transfer_in_id UUID) RETURNS VOID AS $$
DECLARE
    v_event_header JSONB;
    v_tenant_id    UUID;
    v_payload      JSONB;
    v_provision_domain_transfer_in_request_id UUID;
BEGIN

    SELECT build_domain_transfer_payload(
                   p_name := pdtr.domain_name,
                   p_transfer_status := ts.name,
                   p_action_by := pdtr.action_by,
                   p_action_date := pdtr.action_date,
                   p_requested_by := pdtr.tenant_customer_id::TEXT,
                   p_requested_date := pdtr.requested_date,
                   p_expiry_date := pdtr.expiry_date
           ),
           tc.tenant_id,
           COALESCE(pdtr.order_metadata,'{}') || jsonb_build_object('version', '1.0'),
           pdtr.id
    INTO v_payload, v_tenant_id, v_event_header, v_provision_domain_transfer_in_request_id
    FROM provision_domain_transfer_in pdt
             JOIN provision_domain_transfer_in_request pdtr ON pdtr.id = pdt.provision_transfer_request_id
             JOIN transfer_status ts ON ts.id = pdtr.transfer_status_id
             JOIN tdpdb.public.tenant_customer tc ON tc.id = pdtr.tenant_customer_id
    WHERE pdt.id = p_provision_domain_transfer_in_id;

    -- Insert Event for Transfer Away Creation
    PERFORM insert_event(
            p_tenant_id := v_tenant_id,
            p_type_id := tc_id_from_name('event_type', 'domain_transfer'),
            p_payload := v_payload,
            p_header := v_event_header,
            p_reference_id := v_provision_domain_transfer_in_request_id
            );

    RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION provision_domain_transfer_in_success() RETURNS TRIGGER AS $$
BEGIN
    -- domain
    INSERT INTO domain(
        id,
        tenant_customer_id,
        accreditation_tld_id,
        name,
        auth_info,
        roid,
        ry_created_date,
        ry_expiry_date,
        expiry_date,
        ry_updated_date,
        ry_transfered_date,
        tags,
        metadata,
        uname,
        language
    ) (
        SELECT
            pdt.id,    -- domain id
            pdt.tenant_customer_id,
            pdt.accreditation_tld_id,
            pdt.domain_name,
            pdt.pw,
            pdt.roid,
            pdt.ry_created_date,
            pdt.ry_expiry_date,
            pdt.ry_expiry_date,
            pdt.updated_date,
            pdt.ry_transfered_date,
            pdt.tags,
            pdt.metadata,
            pdt.uname,
            pdt.language
        FROM provision_domain_transfer_in pdt
        WHERE id = NEW.id
    );

    -- add linked hosts
    INSERT INTO host(
        tenant_customer_id,
        domain_id,
        name
    )
    SELECT NEW.tenant_customer_id, NEW.id, * FROM UNNEST(NEW.hosts) AS name
    ON CONFLICT (tenant_customer_id,name) DO UPDATE SET domain_id = EXCLUDED.domain_id;

    -- rgp status
    INSERT INTO domain_rgp_status(
        domain_id,
        status_id
    ) VALUES (
        NEW.id,
        tc_id_from_name('rgp_status', 'transfer_grace_period')
    );

    -- secdns data
    if NEW.secdns_type = 'ds_data' then
        WITH new_secdns_ds_data AS (
            INSERT INTO secdns_ds_data(
                key_tag,
                algorithm,
                digest_type,
                digest,
                key_data_id
            )
            SELECT
                pdts.key_tag,
                pdts.algorithm,
                pdts.digest_type,
                pdts.digest,
                pdts.key_data_id
            FROM transfer_in_domain_secdns_ds_data pdts
            WHERE pdts.provision_domain_transfer_in_id = NEW.id
            RETURNING id
            ) INSERT INTO domain_secdns(
                domain_id,
                ds_data_id
            ) SELECT NEW.id, id FROM new_secdns_ds_data;

    ELSIF NEW.secdns_type = 'key_data' then
        WITH new_secdns_key_data AS (
            INSERT INTO secdns_key_data(
                flags,
                protocol,
                algorithm,
                public_key
            )
            SELECT
                pdts.flags,
                pdts.protocol,
                pdts.algorithm,
                pdts.public_key
            FROM transfer_in_domain_secdns_key_data pdts
            WHERE pdts.provision_domain_transfer_in_id = NEW.id
            RETURNING id
            ) INSERT INTO domain_secdns(
                domain_id,
                key_data_id
            ) SELECT NEW.id, id FROM new_secdns_key_data;
    end if;

    --- create domain transfer event
    PERFORM event_domain_transfer_in(NEW.id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



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
