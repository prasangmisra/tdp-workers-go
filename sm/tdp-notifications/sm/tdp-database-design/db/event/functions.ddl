-- Function to insert an event into the event table
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

-- Function to build a JSONB payload for domain transfer
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



