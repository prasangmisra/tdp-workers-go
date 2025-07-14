UPDATE attr_key SET descr='Registry redemption grace period length in hours', default_value=715::TEXT WHERE name='redemption_grace_period';
UPDATE attr_key SET descr='Registry add grace period length in hours', default_value=120::TEXT WHERE name='add_grace_period';
UPDATE attr_key SET descr='Registry transfer grace period length in hours', default_value=120::TEXT WHERE name='transfer_grace_period';
UPDATE attr_key SET descr='Registry auto-renew grace period length in hours', default_value=1080::TEXT WHERE name='autorenew_grace_period';
UPDATE attr_key SET descr='Registry pending grace delete length in hours', default_value=120::TEXT WHERE name='pending_delete_period';


--
-- function: domain_rgp_status_set_expiry_date()
-- description: sets rgp expiry date according to rgp status and tld grace period configuration
--

CREATE OR REPLACE FUNCTION domain_rgp_status_set_expiry_date() RETURNS TRIGGER AS $$
DECLARE
  v_period_hours  INTEGER;
BEGIN

  IF NEW.expiry_date IS NULL THEN

    SELECT value INTO v_period_hours
    FROM v_attribute va
    JOIN domain d ON d.id = NEW.domain_id
    JOIN rgp_status rs ON rs.id = NEW.status_id 
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    WHERE va.key = 'tld.lifecycle.' || rs.name AND va.tld_name = vat.tld_name;

    NEW.expiry_date = NOW() + (v_period_hours || ' hours')::INTERVAL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
