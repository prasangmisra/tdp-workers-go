INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES
      (
          'renewal',
          (SELECT id FROM attr_category WHERE name='period'),
          'List of allowed renewal periods',
          (SELECT id FROM attr_value_type WHERE name='INTEGER_LIST'),
          '{1,2,3,4,5,6,7,8,9,10}'::TEXT,
          FALSE
      ),
      (
          'registration',
          (SELECT id FROM attr_category WHERE name='period'),
          'List of allowed registration periods',
          (SELECT id FROM attr_value_type WHERE name='INTEGER_LIST'),
          '{1,2,3,4,5,6,7,8,9,10}'::TEXT,
          FALSE
      ) on conflict DO NOTHING;


ALTER TABLE order_item_create_domain DROP CONSTRAINT IF EXISTS order_item_create_domain_registration_period_check;

CREATE OR REPLACE FUNCTION validate_period() RETURNS TRIGGER AS $$
DECLARE
    allowed_periods INT[];
    period_to_validate INT;
    period_key TEXT;
    validation_type TEXT;
BEGIN
    -- Determine which period to validate based on the trigger argument
    validation_type := TG_ARGV[0];

    IF validation_type = 'registration' THEN
        period_to_validate := NEW.registration_period;
        period_key := 'tld.period.registration';
    ELSIF validation_type = 'renewal' THEN
        period_to_validate := NEW.period;
        period_key := 'tld.period.renewal';
    ELSE
        RAISE EXCEPTION 'Invalid validation type: %', validation_type;
    END IF;

    SELECT get_tld_setting(
                   p_key => period_key,
                   p_accreditation_tld_id => NEW.accreditation_tld_id
           ) INTO allowed_periods;

    -- Check if the period is within the allowed range
    IF NOT (period_to_validate = ANY(allowed_periods)) THEN
        RAISE EXCEPTION '% period must be one of the allowed values: %',
            validation_type, array_to_string(allowed_periods, ', ');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_period_tg
    BEFORE INSERT OR UPDATE ON order_item_create_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_period('registration');

CREATE TRIGGER validate_period_tg
    BEFORE INSERT OR UPDATE ON order_item_renew_domain
    FOR EACH ROW EXECUTE PROCEDURE validate_period('renewal');
