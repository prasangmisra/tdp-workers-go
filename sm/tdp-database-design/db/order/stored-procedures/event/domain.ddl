-- Function to handle domain transfer away order event
CREATE OR REPLACE FUNCTION event_domain_transfer_away_order()
    RETURNS TRIGGER AS
$$
DECLARE
    v_event_header       JSONB;
    v_tenant_customer_id UUID;
    v_tenant_id          UUID;
    v_payload            JSONB;
BEGIN
    -- Construct event header using order.metadata
    SELECT o.metadata, o.tenant_customer_id, tc.tenant_id
    INTO v_event_header, v_tenant_customer_id, v_tenant_id
    FROM "order" o
             JOIN tenant_customer tc ON o.tenant_customer_id = tc.id
    WHERE o.id = NEW.order_id;

    v_event_header = COALESCE(v_event_header,'{}') || jsonb_build_object('version', '1.0');


    v_payload = build_domain_transfer_payload(
            p_name := NEW.name,
            p_transfer_status := tc_name_from_id('transfer_status', NEW.transfer_status_id),
            p_action_by := v_tenant_customer_id::TEXT,
            p_action_date := NEW.action_date,
            p_requested_by := NEW.requested_by,
            p_requested_date := NEW.requested_date,
            p_expiry_date := NEW.expiry_date
    );

    -- Insert Event for Transfer Away Creation
    PERFORM insert_event(
            p_tenant_id := v_tenant_id,
            p_type_id := tc_id_from_name('event_type', 'domain_transfer'),
            p_payload := v_payload,
            p_reference_id := NEW.domain_id,
            p_header := v_event_header
            );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
