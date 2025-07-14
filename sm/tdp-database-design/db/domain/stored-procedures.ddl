--
-- function: domain_rgp_status_set_expiry_date()
-- description: sets rgp expiry date according to rgp status and tld grace period configuration
--

CREATE OR REPLACE FUNCTION domain_rgp_status_set_expiry_date() RETURNS TRIGGER AS $$
DECLARE
  v_period_hours  INTEGER;
BEGIN

  IF NEW.expiry_date IS NULL THEN

    SELECT get_tld_setting(
        p_key => 'tld.lifecycle.' || tc_name_from_id('rgp_status', NEW.status_id),
        p_accreditation_tld_id=> d.accreditation_tld_id
    ) INTO v_period_hours
    FROM domain d
    WHERE d.id = NEW.domain_id;

    NEW.expiry_date = NOW() + (v_period_hours || ' hours')::INTERVAL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

