-- function: validate_auth_info()
-- description: validates the auth info for a specific order type
CREATE OR REPLACE FUNCTION validate_auth_info() RETURNS TRIGGER AS $$
DECLARE
    order_type                       TEXT;
    v_authcode_mandatory_for_orders  TEXT[];
    v_authcode_supported_for_orders  TEXT[];
    v_authcode_acceptance_criteria   TEXT;
BEGIN
    -- Determine which order type to validate based on the trigger argument
    order_type := TG_ARGV[0];

    -- Get order types that require auth info
    SELECT get_tld_setting(
                   p_key => 'tld.order.authcode_mandatory_for_orders',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO v_authcode_mandatory_for_orders;
    
    -- Get order types that support auth info
    SELECT get_tld_setting(
                   p_key => 'tld.order.authcode_supported_for_orders',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO v_authcode_supported_for_orders;
    
    -- Get the auth info length range
    SELECT get_tld_setting(
                   p_key => 'tld.lifecycle.authcode_acceptance_criteria',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO v_authcode_acceptance_criteria;

    -- Check auth info
    IF NEW.auth_info IS NULL OR NEW.auth_info = '' THEN
        IF order_type = ANY(v_authcode_mandatory_for_orders) THEN
            RAISE EXCEPTION 'Auth info is mandatory for ''%'' order', order_type;
        END IF;
    ELSIF order_type = ANY(ARRAY_CAT(v_authcode_mandatory_for_orders, v_authcode_supported_for_orders)) THEN
        IF NEW.auth_info !~ v_authcode_acceptance_criteria THEN
            RAISE EXCEPTION 'Auth info does not match the required pattern';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
