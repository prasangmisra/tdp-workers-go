--
-- table: rgp_status
-- description: this table lists all posible RGP statuses
--
CREATE TABLE IF NOT EXISTS rgp_status (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  epp_name   TEXT NOT NULL, 
  descr      TEXT NOT NULL,
  UNIQUE (name)
);

INSERT INTO rgp_status (name, epp_name, descr) VALUES
   ('add_grace_period', 'addPeriod', 'registry provides credit for deleted domain during this period for the cost of the registration'),
   ('transfer_grace_period', 'transferPeriod', 'registry provides credit for deleted domain during this period for the cost of the transfer'),
   ('autorenew_grace_period', 'autoRenewPeriod', 'registry provides credit for deleted domain during this period for the cost of the renewal'),
   ('redemption_grace_period', 'redemptionPeriod', 'deleted domain might be restored during this period'),
   ('pending_delete_period', 'pendingDelete', 'deleted domain not restored during redemptionPeriod')
ON CONFLICT DO NOTHING;

--
-- table: domain_rgp_status
-- description: this table joins domain and rgp_status
--

CREATE TABLE IF NOT EXISTS domain_rgp_status
(
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    domain_id           UUID NOT NULL REFERENCES domain,
    status_id           UUID NOT NULL REFERENCES rgp_status,
    created_date        TIMESTAMPTZ DEFAULT NOW(),
    expiry_date         TIMESTAMPTZ NOT NULL
); 

CREATE INDEX IF NOT EXISTS domain_rgp_status_domain_id_idx ON domain_rgp_status(domain_id);
CREATE INDEX IF NOT EXISTS domain_rgp_status_status_id_idx ON domain_rgp_status(status_id);
CREATE INDEX IF NOT EXISTS domain_rgp_expiry_date_id_idx ON domain_rgp_status(expiry_date);


--
-- function: domain_rgp_status_set_expiry_date()
-- description: sets rgp expiry date according to rgp status and tld grace period configuration
--

CREATE OR REPLACE FUNCTION domain_rgp_status_set_expiry_date() RETURNS TRIGGER AS $$
DECLARE
  v_period_days  INTEGER;
BEGIN

  IF NEW.expiry_date IS NULL THEN

    SELECT value INTO v_period_days
    FROM v_attribute va
    JOIN domain d ON d.id = NEW.domain_id
    JOIN rgp_status rs ON rs.id = NEW.status_id 
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    WHERE va.key = 'tld.lifecycle.' || rs.name AND va.tld_name = vat.tld_name;

    NEW.expiry_date = NOW() + (v_period_days || 'days')::INTERVAL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS domain_rgp_status_set_expiration_tg ON domain_rgp_status;
CREATE TRIGGER domain_rgp_status_set_expiration_tg
    BEFORE INSERT ON domain_rgp_status 
    FOR EACH ROW EXECUTE PROCEDURE domain_rgp_status_set_expiry_date();


--
-- view: v_domain
-- description: this view provides extended domain details
--
-- rgp_status: latest, not expired domain registry grace period status
--
DROP VIEW IF EXISTS v_domain;
CREATE OR REPLACE VIEW v_domain AS
SELECT
  d.*,
	rgp.epp_name AS rgp_epp_status
FROM domain d
LEFT JOIN LATERAL (
    SELECT
        rs.epp_name,
        drs.expiry_date
    FROM domain_rgp_status drs
    JOIN rgp_status rs ON rs.id = drs.status_id
    WHERE drs.domain_id = d.id
    ORDER BY created_date DESC
    LIMIT 1
) rgp ON rgp.expiry_date >= NOW();


-- function: provision_domain_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_success() RETURNS TRIGGER AS $$
DECLARE
  s_id UUID;
BEGIN

  SELECT id
  INTO s_id
  FROM domain_status ds
  WHERE ds.name = 'active';

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
    status_id,
    auto_renew
  ) (
    SELECT 
      pd.id,    -- domain id
      pd.tenant_customer_id,
      pd.accreditation_tld_id,
      pd.name,
      pd.pw,
      pd.roid,
      COALESCE(pd.ry_created_date,pd.created_date),
      COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
      COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
      s_id as status_id,
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

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null
)
VALUES
(
    'add_grace_period',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry add grace period length in days',
    (SELECT id FROM attr_value_type WHERE name='INTEGER'),
    5::TEXT,
    FALSE
),
(
    'transfer_grace_period',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry transfer grace period length in days',
    (SELECT id FROM attr_value_type WHERE name='INTEGER'),
    5::TEXT,
    FALSE
),
(
    'autorenew_grace_period',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry auto-renew grace period length in days',
    (SELECT id FROM attr_value_type WHERE name='INTEGER'),
    45::TEXT,
    FALSE
),
(
    'pending_delete_period',
    (SELECT id FROM attr_category WHERE name='lifecycle'),
    'Registry pending grace delete length in days',
    (SELECT id FROM attr_value_type WHERE name='INTEGER'),
    5::TEXT,
    FALSE
)
ON CONFLICT DO NOTHING;
