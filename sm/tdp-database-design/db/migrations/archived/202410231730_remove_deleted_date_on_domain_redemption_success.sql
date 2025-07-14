-- function: provision_domain_redeem_success
-- description: redeems the domain in the domain table along with contacts and hosts references
CREATE OR REPLACE FUNCTION provision_domain_redeem_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE domain_rgp_status SET
        expiry_date = NOW()
    WHERE id = (SELECT rgp_status_id FROM v_domain where id = NEW.domain_id and rgp_epp_status = 'redemptionPeriod');

    UPDATE domain SET
        deleted_date = NULL
    WHERE id = NEW.domain_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
