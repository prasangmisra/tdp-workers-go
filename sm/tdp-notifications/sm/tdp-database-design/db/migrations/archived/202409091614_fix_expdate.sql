DROP TRIGGER IF EXISTS validate_renew_order_domain_exists_tg ON order_item_renew_domain;
DROP FUNCTION IF EXISTS validate_renew_order_domain_exists();

INSERT INTO attr_key(name,
                     category_id,
                     descr,
                     value_type_id,
                     default_value,
                     allow_null)
VALUES (
           'max_lifetime',
           (SELECT id FROM attr_category WHERE name='lifecycle'),
           'max lifetime of a domain in years',
           (SELECT id FROM attr_value_type WHERE name='INTEGER'),
           10::TEXT,
           FALSE
       ) ON CONFLICT DO NOTHING;


CREATE OR REPLACE FUNCTION validate_renew_order_expiry_date() RETURNS TRIGGER AS $$
DECLARE
    v_domain RECORD;
    max_lifetime INT;
BEGIN
    -- Fetch the domain record based on the name
    SELECT * INTO v_domain
    FROM domain
    WHERE name = NEW.name;

    -- Validate the expiry date matches the stored expiry date
    IF NEW.current_expiry_date::DATE != v_domain.ry_expiry_date::DATE THEN
        RAISE EXCEPTION 'The provided expiry date % does not match the current expiry date %',
            NEW.current_expiry_date::DATE, v_domain.ry_expiry_date::DATE;
    END IF;

    SELECT get_tld_setting(
                   p_key => 'tld.lifecycle.max_lifetime',
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO max_lifetime;

    -- Validate that the new renewal period doesn't exceed the maximum allowed lifetime
    IF v_domain.ry_expiry_date + (NEW.period || ' years')::INTERVAL > NOW() + (max_lifetime || ' years')::INTERVAL THEN
        RAISE EXCEPTION 'The renewal period of % years exceeds the maximum allowed lifetime of % years for the TLD',
            NEW.period, max_lifetime;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS validate_renew_order_expiry_date_tg ON order_item_renew_domain;
CREATE OR REPLACE TRIGGER validate_renew_order_expiry_date_tg
    BEFORE INSERT ON order_item_renew_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_renew_order_expiry_date();

