INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null
) 
VALUES 
(
  'authcode_supported_for_orders',
  (SELECT id FROM attr_category WHERE name='order'),
  'List of order types which support authcode',
  (SELECT id FROM attr_value_type WHERE name='TEXT_LIST'),
  ARRAY['registration','transfer_in','update','owner_change']::TEXT,
  FALSE
),
(
  'authcode_length',
  (SELECT id FROM attr_category WHERE name='lifecycle'),
  'Range of minimum and maximum authcode length',
  (SELECT id FROM attr_value_type WHERE name='INT4RANGE'),
  '[6, 16]'::TEXT,
  FALSE
) ON CONFLICT DO NOTHING;



-- function: validate_auth_info()
-- description: validates the auth info for a specific order type
CREATE OR REPLACE FUNCTION validate_auth_info() RETURNS TRIGGER AS $$
DECLARE
    order_type                       TEXT;
    v_authcode_mandatory_for_orders  TEXT[];
    v_authcode_supported_for_orders  TEXT[];
    v_authcode_length                INT4RANGE;
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
                   p_key => 'tld.lifecycle.authcode_length',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO v_authcode_length;

    -- Check auth info
    IF NEW.auth_info IS NULL OR NEW.auth_info = '' THEN
        IF order_type = ANY(v_authcode_mandatory_for_orders) THEN
            RAISE EXCEPTION 'Auth info is mandatory for ''%'' order', order_type;
        END IF;
    ELSIF order_type = ANY(v_authcode_supported_for_orders) THEN
        IF NOT v_authcode_length @> LENGTH(NEW.auth_info) THEN
            RAISE EXCEPTION 'Auth info length must be in this range [%-%]', lower(v_authcode_length), upper(v_authcode_length)-1;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER validate_auth_info_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_auth_info('registration');

CREATE OR REPLACE TRIGGER validate_auth_info_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_auth_info('update');

CREATE OR REPLACE TRIGGER validate_auth_info_tg
    BEFORE UPDATE ON order_item_transfer_away_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_auth_info('transfer_away');
