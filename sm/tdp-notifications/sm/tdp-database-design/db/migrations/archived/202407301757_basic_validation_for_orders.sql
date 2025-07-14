-- insert new attr_key
INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES
(
    'is_registration_allowed',
    (SELECT id FROM attr_category WHERE name='order'),
    'Registry supports domain registration',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
),
(
    'is_delete_allowed',
    (SELECT id FROM attr_category WHERE name='order'),
    'Registry supports domain delete',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
),
(
    'is_redeem_allowed',
    (SELECT id FROM attr_category WHERE name='order'),
    'Registry supports domain redemption',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
),
(
    'is_renew_allowed',
    (SELECT id FROM attr_category WHERE name='order'),
    'Registry supports domain renew',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
),
(
    'is_update_allowed',
    (SELECT id FROM attr_category WHERE name='order'),
    'Registry supports domain update',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
),
(
    'is_tld_active',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Is TLD active',
    (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
    TRUE::TEXT,
    FALSE
),
(
    'domain_length',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Range of minimum and maximum domain length',
    (SELECT id FROM attr_value_type WHERE name='INT4RANGE'),
    '[3, 63]'::TEXT,
    TRUE
);


-- function: domain_name_part
-- description: returns domain name part of a fqdn (domain name or hostname).
CREATE OR REPLACE FUNCTION domain_name_part(fqdn TEXT) RETURNS TEXT AS $$
DECLARE
    v_tld TEXT;
BEGIN
    v_tld := tld_part(fqdn);
    RETURN SUBSTRING(fqdn FROM 1 FOR LENGTH(fqdn) - LENGTH('.' || v_tld));
END;
$$ LANGUAGE plpgsql;


-- function: validate_domain_order_type()
-- description: validates if the domain order type is allowed for the TLD
CREATE OR REPLACE FUNCTION validate_domain_order_type() RETURNS TRIGGER AS $$
DECLARE
    v_is_order_allowed    BOOLEAN;
    key            TEXT;
    order_type            TEXT;
BEGIN
    order_type := TG_ARGV[0];

    IF order_type = 'registration' THEN
        key := 'tld.order.is_registration_allowed';
    ELSIF order_type = 'renew' THEN
        key := 'tld.order.is_renew_allowed';
    ELSIF order_type = 'delete' THEN
        key := 'tld.order.is_delete_allowed';
    ELSIF order_type = 'redeem' THEN
        key := 'tld.order.is_redeem_allowed';
    ELSIF order_type = 'update' THEN
        key := 'tld.order.is_update_allowed';
    ELSIF order_type = 'transfer_in' THEN
        key := 'tld.order.is_transfer_allowed';
    ELSE
        RAISE EXCEPTION 'Invalid order type: %', order_type;
    END IF;

    SELECT get_tld_setting(
                   p_key=>key,
                   p_accreditation_tld_id=>NEW.accreditation_tld_id
           ) INTO v_is_order_allowed;

    IF NOT v_is_order_allowed THEN
        RAISE EXCEPTION 'TLD ''%'' does not support domain %', tld_part(NEW.name), order_type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_domain_syntax()
-- description: validates the syntax of a domain name
CREATE OR REPLACE FUNCTION validate_domain_syntax() RETURNS TRIGGER AS $$
DECLARE
    v_length_range   INT4RANGE;
    v_name           TEXT;
BEGIN
    SELECT get_tld_setting(
                   p_key=>'tld.lifecycle.domain_length',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           )
    INTO v_length_range;

    SELECT domain_name_part(NEW.name) INTO v_name;

    -- Check if the domain name length is within the allowed range
    IF NOT v_length_range @> LENGTH(v_name) THEN
        RAISE EXCEPTION 'Domain name length must be in this range [%-%]', lower(v_length_range), upper(v_length_range)-1;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: validate_tld_active()
-- description: validates if the TLD is active
CREATE OR REPLACE FUNCTION validate_tld_active() RETURNS TRIGGER AS $$
DECLARE
    v_is_tld_active BOOLEAN;
BEGIN
    SELECT get_tld_setting(
                   p_key=>'tld.lifecycle.is_tld_active',
                   p_accreditation_tld_id=>NEW.accreditation_tld_id
           ) INTO v_is_tld_active;

    IF NOT v_is_tld_active THEN
        RAISE EXCEPTION 'TLD ''%'' is not active', tld_part(NEW.name);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS order_prevent_if_domain_transfer_unsupported_tg ON order_item_transfer_in_domain;
DROP FUNCTION IF EXISTS order_prevent_if_domain_transfer_unsupported();

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain create is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('registration');

-- prevent order creation if domain syntax is invalid
CREATE TRIGGER validate_domain_syntax_tg
    BEFORE INSERT ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_syntax();

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain delete is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('delete');

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_redeem_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain registration is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_redeem_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('redeem');

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_renew_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain renew is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_renew_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('renew');

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_transfer_in_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain transfer is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_transfer_in_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('transfer_in');

-- prevent order creation if domain syntax is invalid
CREATE TRIGGER validate_domain_syntax_tg
    BEFORE INSERT ON order_item_transfer_in_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_syntax();

-- prevents order creation if tld is not active
CREATE TRIGGER validate_tld_active_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_tld_active();

-- prevents order creation if domain update is unsupported
CREATE TRIGGER validate_domain_order_type_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_domain_order_type('update');
