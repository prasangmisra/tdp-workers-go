CREATE OR REPLACE FUNCTION domain_rgp_status_set_expiry_date() RETURNS TRIGGER AS $$
DECLARE
  v_period_hours  INTEGER;
BEGIN

  IF NEW.expiry_date IS NULL THEN

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.' || rs.name,
        p_tld_name=>vat.tld_name
    ) INTO v_period_hours
    FROM domain d
    JOIN rgp_status rs ON rs.id = NEW.status_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    WHERE d.id = NEW.domain_id;

    NEW.expiry_date = NOW() + (v_period_hours || ' hours')::INTERVAL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

