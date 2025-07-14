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
