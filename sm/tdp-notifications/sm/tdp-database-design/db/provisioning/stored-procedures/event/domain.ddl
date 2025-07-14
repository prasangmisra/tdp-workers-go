-- Function to handle domain transfer in request event
CREATE OR REPLACE FUNCTION event_domain_transfer_in_request()
    RETURNS TRIGGER AS
$$
DECLARE
    v_event_header JSONB;
    v_tenant_id    UUID;
    v_payload      JSONB;
BEGIN
    SELECT tenant_customer.tenant_id
    INTO v_tenant_id
    FROM tenant_customer
    WHERE id = NEW.tenant_customer_id;

    v_event_header = COALESCE(NEW.order_metadata,'{}') || jsonb_build_object('version', '1.0');



    v_payload = build_domain_transfer_payload(
            p_name := NEW.domain_name,
            p_transfer_status := tc_name_from_id('transfer_status', NEW.transfer_status_id),
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
