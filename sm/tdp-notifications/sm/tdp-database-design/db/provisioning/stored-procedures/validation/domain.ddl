-- function: provision_domain_renew_check_exp_date
-- description: checks if the current_expiry_date matches the ry_expiry_date in the domain table
CREATE OR REPLACE FUNCTION provision_domain_renew_check_exp_date() RETURNS TRIGGER AS $$
DECLARE
    valid_date BOOL;
BEGIN

    SELECT EXISTS(
        SELECT TRUE FROM domain WHERE DATE(ry_expiry_date)=DATE(NEW.current_expiry_date)
                                  AND id = NEW.domain_id
    ) INTO valid_date;

    IF NOT valid_date THEN
        RAISE EXCEPTION 'request current_expiry_date does not match ry_expiry_date in domain table';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE PLPGSQL;
