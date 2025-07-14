-- remove v_domain view because it depends on column status_id of table domain
DROP VIEW IF EXISTS v_domain;

-- drop domain_status table
DROP TABLE IF EXISTS domain_status CASCADE;

-- remove status_id column from domain table
ALTER TABLE IF EXISTS domain DROP COLUMN IF EXISTS status_id;

-- remove domain_status_id_fkey constraint from domain table
ALTER TABLE IF EXISTS domain DROP CONSTRAINT IF EXISTS domain_status_id_fkey;

-- drop domain_force_initial_status_tg trigger
DROP TRIGGER IF EXISTS domain_force_initial_status_tg ON domain;

-- drop domain_force_initial_status funtion
DROP FUNCTION IF EXISTS domain_force_initial_status();

-- add domain_id column to order_item_delete_domain table
ALTER TABLE IF EXISTS order_item_delete_domain ADD COLUMN IF NOT EXISTS domain_id UUID REFERENCES domain;

-- populates domain id column and sets to be not null
UPDATE order_item_delete_domain oidd
SET domain_id = d.id 
FROM domain d
WHERE oidd.name = d.name AND oidd.domain_id IS NULL;

ALTER TABLE IF EXISTS order_item_delete_domain ALTER COLUMN domain_id SET NOT NULL;

-- v_domain view
CREATE OR REPLACE VIEW v_domain AS
SELECT
  d.*,
  rgp.id AS rgp_status_id,
  rgp.epp_name AS rgp_epp_status
FROM domain d
LEFT JOIN LATERAL (
    SELECT
        rs.epp_name,
        drs.id,
        drs.expiry_date
    FROM domain_rgp_status drs
    JOIN rgp_status rs ON rs.id = drs.status_id
    WHERE drs.domain_id = d.id
    ORDER BY created_date DESC
    LIMIT 1
) rgp ON rgp.expiry_date >= NOW();



-- function: order_prevent_if_nameservers_count_is_invalid()
-- description: Check if nameservers count match TLD settings
CREATE OR REPLACE FUNCTION order_prevent_if_nameservers_count_is_invalid() RETURNS TRIGGER AS $$
DECLARE
    v_domain        RECORD;
    _min_ns_attr    INT;
    _max_ns_attr    INT;
    _hosts_count    INT;
BEGIN
    SELECT * INTO v_domain
    FROM domain d
    JOIN "order" o ON o.id=NEW.order_id
    WHERE d.name=NEW.name
      AND d.tenant_customer_id=o.tenant_customer_id;

    SELECT va.value::INT INTO _min_ns_attr
    FROM v_attribute va
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_domain.accreditation_tld_id
    WHERE va.key = 'tld.dns.min_nameservers'
      AND va.tld_name = vat.tld_name;

    SELECT va.value::INT INTO _max_ns_attr
    FROM v_attribute va
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_domain.accreditation_tld_id
    WHERE va.key = 'tld.dns.max_nameservers'
      AND va.tld_name = vat.tld_name;

    SELECT CARDINALITY(NEW.hosts) INTO _hosts_count;

    IF _hosts_count < _min_ns_attr OR _hosts_count > _max_ns_attr THEN
        RAISE EXCEPTION 'Nameserver count must be in this range %-%', _min_ns_attr,_max_ns_attr;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_success() RETURNS TRIGGER AS $$
DECLARE
  s_id UUID;
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

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_if_domain_does_not_exist()
-- description: check if domain from order data exists
CREATE OR REPLACE FUNCTION order_prevent_if_domain_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    v_domain    RECORD;
BEGIN
  IF NEW.domain_id IS NULL THEN
    SELECT * INTO v_domain
    FROM domain d
    JOIN "order" o ON o.id=NEW.order_id
    WHERE d.name=NEW.name
      AND d.tenant_customer_id=o.tenant_customer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Domain ''%'' not found', NEW.name USING ERRCODE = 'no_data_found';
    END IF;

    NEW.domain_id = v_domain.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- drop order_prevent_if_domain_does_not_exist_tg trigger
DROP TRIGGER IF EXISTS order_prevent_if_domain_does_not_exist_tg ON order_item_redeem_domain;

-- check if domain from order data exists
CREATE TRIGGER order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_redeem_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();


-- function: order_prevent_if_domain_is_deleted()
-- description: check if the domain on the order data is deleted
CREATE OR REPLACE FUNCTION order_prevent_if_domain_is_deleted() RETURNS TRIGGER AS $$
BEGIN
  PERFORM TRUE FROM v_domain WHERE name=NEW.name and rgp_epp_status IN ('redemptionPeriod', 'pendingDelete');

  IF FOUND THEN
    RAISE EXCEPTION 'Domain ''%'' is deleted domain', NEW.name USING ERRCODE = 'no_data_found';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- order_prevent_if_domain_is_deleted_tg trigger ON order_item_update_domain
DROP TRIGGER IF EXISTS order_prevent_if_domain_is_deleted_tg ON order_item_update_domain;
CREATE TRIGGER order_prevent_if_domain_is_deleted_tg
    BEFORE INSERT ON order_item_update_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_is_deleted();

-- order_prevent_if_domain_is_deleted_tg trigger ON order_item_renew_domain
DROP TRIGGER IF EXISTS order_prevent_if_domain_is_deleted_tg ON order_item_renew_domain;
CREATE TRIGGER order_prevent_if_domain_is_deleted_tg
    BEFORE INSERT ON order_item_renew_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_is_deleted();

-- order_prevent_if_domain_is_deleted_tg trigger ON order_item_delete_domain
DROP TRIGGER IF EXISTS order_prevent_if_domain_is_deleted_tg ON order_item_delete_domain;
CREATE TRIGGER order_prevent_if_domain_is_deleted_tg
    BEFORE INSERT ON order_item_delete_domain 
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_is_deleted();


-- function: validate_domain_in_redemption_period()
-- description: validates domain in grace period
CREATE OR REPLACE FUNCTION validate_domain_in_redemption_period() RETURNS TRIGGER AS $$
BEGIN
  PERFORM TRUE FROM v_domain WHERE name=NEW.name and rgp_epp_status = 'redemptionPeriod';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Domain ''%'' not in redemption grace period', NEW.name;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_delete_success
-- description: deletes the domain in the domain table along with contacts and hosts references 
CREATE OR REPLACE FUNCTION provision_domain_delete_success() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO domain_rgp_status(
    domain_id,
    status_id
  ) VALUES (
    NEW.domain_id,
    tc_id_from_name('rgp_status', 'redemption_grace_period')
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_redeem_success
-- description: redeems the domain in the domain table along with contacts and hosts references 
CREATE OR REPLACE FUNCTION provision_domain_redeem_success() RETURNS TRIGGER AS $$
BEGIN
  UPDATE domain_rgp_status SET
    expiry_date = NOW()
  WHERE id = (SELECT rgp_status_id FROM v_domain where id = NEW.domain_id and rgp_epp_status = 'redemptionPeriod');
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
