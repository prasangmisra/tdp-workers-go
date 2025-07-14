-- Purpose: Add is_private column to history.domain_contact table.
--

ALTER TABLE IF EXISTS history.domain_contact ADD IF NOT EXISTS is_private BOOLEAN;


--
-- function: delete_domain_with_reason( _domain_id UUID, _reason TEXT)
-- description: 
-- 
CREATE OR REPLACE FUNCTION delete_domain_with_reason( _domain_id UUID, _reason TEXT)
RETURNS void AS $$
BEGIN
  IF _reason IS NULL THEN 
    RAISE EXCEPTION 'No reason provided for domain deletion';
  END IF; 

  -- 1. add record to history.domain table 
  INSERT INTO history.domain (
    reason,
    id,
    tenant_customer_id,
    tenant_name,
    customer_name,
    accreditation_tld_id,
    name,
    auth_info,
    roid,
    ry_created_date,
    ry_expiry_date,
    ry_updated_date,
    ry_transfered_date,
    deleted_date,
    expiry_date,
    auto_renew,
    secdns_max_sig_life,
    tags,
    metadata,
    uname,
    language,
    migration_info
  )
  SELECT
    _reason,
    d.id,
    d.tenant_customer_id,
    vtc.tenant_name,
    vtc.name AS customer_name,
    d.accreditation_tld_id,
    d.name,
    d.auth_info,
    d.roid,
    d.ry_created_date,
    d.ry_expiry_date,
    d.ry_updated_date,
    d.ry_transfered_date,
    d.deleted_date,
    d.expiry_date,
    d.auto_renew,
    d.secdns_max_sig_life,
    d.tags,
    d.metadata,
    d.uname,
    d.language,
    d.migration_info
  FROM domain d
  JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
  WHERE d.id = _domain_id;

  -- 2. add record to contact
  WITH history_contact AS (
    INSERT INTO history.contact(   
      orig_id,
      type_id, 
      title,
      org_reg,
      org_vat,
      org_duns,
      tenant_customer_id,
      email,
      phone,
      fax,
      country,
      language,  
      tags,
      documentation,
      short_id,
      metadata,
      migration_info
    )
    SELECT DISTINCT ON (c.id)
      c.id,
      c.type_id,
      c.title,
      c.org_reg,
      c.org_vat,
      c.org_duns,
      c.tenant_customer_id,
      c.email,
      c.phone,
      c.fax,
      c.country,
      c.language,
      c.tags,
      c.documentation,
      c.short_id,
      c.metadata,
      c.migration_info
    FROM domain_contact dc
    JOIN ONLY contact c ON c.id = dc.contact_id
    WHERE dc.domain_id = _domain_id
    RETURNING id, orig_id
  ),
  history_contact_postal AS(
    INSERT INTO history.contact_postal(
      orig_id,
      contact_id,
      is_international,
      first_name,
      last_name,
      org_name,
      address1,
      address2,
      address3,
      city,
      postal_code,
      state
    )
    SELECT
      cp.id,
      hc.id,
      cp.is_international,
      cp.first_name,
      cp.last_name,
      cp.org_name,
      cp.address1,
      cp.address2,
      cp.address3,
      cp.city,
      cp.postal_code,
      cp.state
    FROM ONLY contact_postal cp
    JOIN history_contact hc ON hc.orig_id = cp.contact_id
  ),
  history_contact_attribute AS (
    INSERT INTO history.contact_attribute(
      attribute_id,
      attribute_type_id,
      contact_id,
      value
    )
    SELECT
      ca.attribute_id,
      ca.attribute_type_id,
      hc.id,
      ca.value
    FROM ONLY contact_attribute ca
    JOIN history_contact hc ON hc.orig_id = ca.contact_id
  )
  INSERT INTO history.domain_contact(
    domain_id,
    contact_id,
    domain_contact_type_id,
    handle,
    is_local_presence,
    is_privacy_proxy,
    is_private
  )
  SELECT
    dc.domain_id,
    hc.id,
    dc.domain_contact_type_id,
    dc.handle,
    dc.is_local_presence,
    dc.is_privacy_proxy,
    dc.is_private
  FROM domain_contact dc
  JOIN history_contact hc ON hc.orig_id = dc.contact_id
  WHERE dc.domain_id = _domain_id;

  -- 3. add record to host
  WITH history_host AS (
    INSERT INTO history.host(
      orig_id,
      tenant_customer_id,
      name,
      domain_id,
      tags,
      metadata
    )
    SELECT
      h.id,
      h.tenant_customer_id,
      h.name,
      h.domain_id,
      h.tags,
      h.metadata
    FROM domain_host dh 
    JOIN ONLY host h ON h.id = dh.host_id
    WHERE dh.domain_id = _domain_id
    RETURNING id, orig_id
  ),
  history_host_addr AS (
    INSERT INTO history.host_addr (
      host_id,
      address
    )
    SELECT
      hh.id,
      ha.address
    FROM ONLY host_addr ha
    JOIN history_host hh ON hh.orig_id = ha.host_id
  )
  INSERT INTO history.domain_host(
    domain_id,
    host_id
  )
  SELECT _domain_id, hh.id FROM history_host hh;

  -- 4. add record to dns
  WITH history_secdns_ds_key_data AS (
    INSERT INTO history.secdns_key_data(
      orig_id,
      flags,
      protocol,
      algorithm,
      public_key
    )
    SELECT
      skd.id,
      skd.flags,
      skd.protocol,
      skd.algorithm,
      skd.public_key
    FROM domain_secdns ds
    JOIN ONLY secdns_ds_data sdd ON sdd.id = ds.ds_data_id
    JOIN ONLY secdns_key_data skd ON skd.id = sdd.key_data_id
    WHERE ds.domain_id = _domain_id AND ds.ds_data_id IS NOT NULL
    RETURNING id, orig_id
  ),
  history_secdns_ds_data AS (
    INSERT INTO history.secdns_ds_data(
      orig_id,
      key_tag,
      algorithm,
      digest_type,
      digest,
      key_data_id
    )
    SELECT
      sdd.id,
      sdd.key_tag,
      sdd.algorithm,
      sdd.digest_type,
      sdd.digest,
      hsdkd.id
    FROM domain_secdns ds
    JOIN ONLY secdns_ds_data sdd ON sdd.id = ds.ds_data_id
    LEFT JOIN history_secdns_ds_key_data hsdkd ON hsdkd.orig_id = sdd.key_data_id
    WHERE ds.domain_id = _domain_id AND ds.ds_data_id IS NOT NULL
    RETURNING id
  ),
  history_secdns_key_data AS (
    INSERT INTO history.secdns_key_data(
      orig_id,
      flags,
      protocol,
      algorithm,
      public_key
    )
    SELECT
      skd.id,
      skd.flags,
      skd.protocol,
      skd.algorithm,
      skd.public_key
    FROM domain_secdns ds
    JOIN ONLY secdns_key_data skd ON skd.id = ds.key_data_id
    WHERE ds.domain_id = _domain_id AND ds.key_data_id IS NOT NULL
    RETURNING id
  )
  INSERT INTO history.domain_secdns(
    domain_id,
    ds_data_id,
    key_data_id
  )
  SELECT _domain_id, hsdd.id, NULL FROM history_secdns_ds_data hsdd

  UNION

  SELECT _domain_id, NULL, hskd.id FROM history_secdns_key_data hskd;

  -- 5 delete decord from domain; information will be deleted on cascade from related 8 tables;  
  DELETE FROM domain 
  WHERE domain.id = _domain_id;
END;
$$ LANGUAGE plpgsql;
