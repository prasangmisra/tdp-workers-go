CREATE OR REPLACE FUNCTION insert_event(
    p_tenant_id UUID,
    p_type_id UUID,
    p_payload JSONB,
    p_reference_id UUID DEFAULT NULL,
    p_header JSONB DEFAULT NULL
)
    RETURNS UUID AS
$$
DECLARE
    v_event_id               UUID;
    v_event_creation_enabled BOOLEAN;
BEGIN
    SELECT COALESCE(vav.value::BOOLEAN, false)
    INTO v_event_creation_enabled
    FROM v_attr_value vav
    WHERE tenant_id = p_tenant_id
      AND vav.category_name = 'event'
      AND vav.key_name = 'is_event_creation_enabled';

    IF NOT v_event_creation_enabled THEN
        RETURN NULL; -- Event creation is disabled
    END IF;


    -- Insert into the event table
    INSERT INTO event (tenant_id,
                       type_id,
                       payload,
                       reference_id,
                       header)
    VALUES (p_tenant_id,
            p_type_id,
            p_payload,
            p_reference_id,
            p_header)
    RETURNING id INTO v_event_id;

    -- Return the generated event ID
    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION build_domain_transfer_payload(
    p_name TEXT,
    p_transfer_status TEXT,
    p_action_by TEXT,
    p_action_date TIMESTAMP with time zone,
    p_requested_by TEXT,
    p_requested_date TIMESTAMP with time zone,
    p_expiry_date TIMESTAMP with time zone DEFAULT NULL
)
    RETURNS JSONB AS
$$
BEGIN
    RETURN jsonb_build_object(
            'name', p_name,
            'status', p_transfer_status,
            'actionBy', p_action_by,
            'actionDate', p_action_date,
            'requestedBy', p_requested_by,
            'requestedDate', p_requested_date,
            'expiryDate', p_expiry_date
           );
END;
$$ LANGUAGE plpgsql;



INSERT INTO event_type (name, reference_table_name, description)
VALUES ('domain_transfer', 'domain', 'Domain transfer event') ON CONFLICT DO NOTHING;


----------------- Transfer In Order Event-----------------
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



CREATE TRIGGER event_domain_transfer_in_request_tg
    AFTER UPDATE OF transfer_status_id ON provision_domain_transfer_in_request
    FOR EACH ROW
    WHEN (NEW.transfer_status_id IS NOT NULL)
EXECUTE PROCEDURE event_domain_transfer_in_request();


----------------- Transfer Away Order Event-----------------
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

CREATE TRIGGER event_domain_transfer_away_order_tg
    AFTER INSERT OR UPDATE OF transfer_status_id ON order_item_transfer_away_domain
    FOR EACH ROW
    WHEN (NEW.transfer_status_id IS NOT NULL)
EXECUTE PROCEDURE event_domain_transfer_away_order();
