-- function: provision_domain_delete_success
-- description: deletes the domain in the domain table along with contacts and hosts references 
CREATE OR REPLACE FUNCTION provision_domain_delete_success() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.in_redemption_grace_period THEN
    INSERT INTO domain_rgp_status(
      domain_id,
      status_id
    ) VALUES (
      NEW.domain_id,
      tc_id_from_name('rgp_status', 'redemption_grace_period')
    );

    UPDATE domain
    SET deleted_date = NOW()
    WHERE id = NEW.domain_id;
  ELSE
    DELETE FROM domain
    WHERE id = NEW.domain_id;

    DELETE FROM provision_domain
    WHERE domain_name = NEW.domain_name;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
