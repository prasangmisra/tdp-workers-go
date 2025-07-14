-- drop old funtion
DROP TRIGGER IF EXISTS provision_domain_status_update_tg ON provision_domain;
DROP FUNCTION IF EXISTS provision_domain_status_update();

-- function: provision_domain_success()
-- description: complete or continue provision order based on the status
CREATE OR REPLACE FUNCTION provision_domain_success() RETURNS TRIGGER AS $$
BEGIN
  -- domain
  INSERT INTO domain(
      id,
      tenant_customer_id,
      accreditation_tld_id,
      name,
      auth_info,
      roid,
      ry_created_date,
      ry_expiry_date,
      expiry_date,
      auto_renew
  ) (
      SELECT
          pd.id,    -- domain id
          pd.tenant_customer_id,
          pd.accreditation_tld_id,
          pd.domain_name,
          pd.pw,
          pd.roid,
          COALESCE(pd.ry_created_date,pd.created_date),
          COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
          COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
          pd.auto_renew
      FROM provision_domain pd
      WHERE id = NEW.id
  );

  -- contact association
  INSERT INTO domain_contact(
      domain_id,
      contact_id,
      domain_contact_type_id,
      handle
  ) (
      SELECT
          pdc.provision_domain_id,
          pdc.contact_id,
          pdc.contact_type_id,
          pc.handle
      FROM provision_domain_contact pdc
                JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
      WHERE pdc.provision_domain_id = NEW.id
  );

  -- host association
  INSERT INTO domain_host(
      domain_id,
      host_id
  ) (
      SELECT
          provision_domain_id,
          host_id
      FROM provision_domain_host
      WHERE provision_domain_id = NEW.id
  );

  -- rgp status
  INSERT INTO domain_rgp_status(
      domain_id,
      status_id
  ) VALUES (
        NEW.id,
        tc_id_from_name('rgp_status', 'add_grace_period')
    );

  -- start the provision domain update
  IF NEW.parent_id IS NOT NULL THEN
      UPDATE provision_domain_update 
      SET is_complete = TRUE, domain_id = NEW.id
      WHERE id = NEW.parent_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_failure()
-- description: fail provision order based on the status
CREATE OR REPLACE FUNCTION provision_domain_failure() RETURNS TRIGGER AS $$
BEGIN
    -- fail the provision domain update
    IF NEW.parent_id IS NOT NULL THEN
        UPDATE provision_domain_update 
        SET status_id = NEW.status_id 
        WHERE id = NEW.parent_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- trigger: provision_domain_success_tg
CREATE OR REPLACE TRIGGER provision_domain_success_tg
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    NEW.is_complete 
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_success();

-- COMMENT ON TRIGGER provision_domain_success_tg IS 'creates the domain after the provision_domain is done';


-- trigger: provision_domain_failure_tg
CREATE OR REPLACE TRIGGER provision_domain_failure_tg
  AFTER UPDATE ON provision_domain
  FOR EACH ROW WHEN (
    NEW.is_complete 
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','failed')
  ) EXECUTE PROCEDURE provision_domain_failure();

-- COMMENT ON TRIGGER provision_domain_failure_tg IS 'fail the provision domain';

