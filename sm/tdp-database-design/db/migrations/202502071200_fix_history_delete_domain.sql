CREATE OR REPLACE FUNCTION delete_domain_with_reason( _domain_id UUID, _reason TEXT)
RETURNS void AS $$

DECLARE
  _id_cont UUID[];
  id_cont UUID;  
  _id_host UUID[]; 
  id_host UUID; 
  _id_dns UUID[];
  id_dns UUID;
  _id_dns2 UUID[];
  id_dns2 UUID;

BEGIN
  IF _reason IS NULL THEN 
    RAISE EXCEPTION 'No reason provided for domain deletion';
  END IF; 

  -- 1. add record to history.domain table 
  INSERT INTO history.domain 
    (reason 
    ,id
    ,tenant_customer_id
    ,tenant_name
    ,customer_name
    ,accreditation_tld_id
    ,name
    ,auth_info
    ,roid
    ,ry_created_date
    ,ry_expiry_date
    ,ry_updated_date
    ,ry_transfered_date
    ,deleted_date
    ,expiry_date
    ,auto_renew
    ,secdns_max_sig_life
    ,tags
    ,metadata
    ,uname
    ,language
    ,migration_info
    ) 
    SELECT 
      _reason 
      , d.id
      , d.tenant_customer_id
      , vtc.tenant_name
      , vtc.name AS customer_name
      , d.accreditation_tld_id
      , d.name
      , d.auth_info
      , d.roid
      , d.ry_created_date
      , d.ry_expiry_date
      , d.ry_updated_date
      , d.ry_transfered_date
      , d.deleted_date
      , d.expiry_date
      , d.auto_renew
      , d.secdns_max_sig_life
      , d.tags
      , d.metadata
      , d.uname
      , d.language
      , d.migration_info
    FROM domain d
    JOIN v_tenant_customer vtc ON vtc.id = d.tenant_customer_id
    WHERE d.id = _domain_id;

  -- 2. add record to contact

  WITH inserted AS (
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
      migration_info)
      SELECT c.id, 
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
      LEFT JOIN ONLY contact c ON c.id = dc.contact_id
      WHERE dc.domain_id = _domain_id
    RETURNING id
  )SELECT array_agg(id) INTO _id_cont FROM inserted;

  IF _id_cont IS NOT NULL THEN

    FOREACH id_cont IN ARRAY _id_cont
      LOOP
      RAISE NOTICE 'id_cont %', id_cont; 

      INSERT INTO history.domain_contact(  
        id,
        domain_id,
        contact_id,
        domain_contact_type_id,
        is_local_presence,
        is_privacy_proxy,
        handle)
        SELECT 
          dc.id,
          dc.domain_id,
          id_cont,
          dc.domain_contact_type_id,
          dc.is_local_presence,
          dc.is_privacy_proxy,
          dc.handle
        FROM domain_contact dc 
        JOIN history.contact c ON c.orig_id = dc.contact_id
        WHERE dc.domain_id = _domain_id
          AND c.id = id_cont; 

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
        state)
        SELECT 
          cp.id, 
          id_cont,
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
        FROM domain_contact dc
        JOIN history.contact c ON c.orig_id = dc.contact_id
        JOIN ONLY contact_postal cp ON cp.contact_id = dc.contact_id 
        WHERE dc.domain_id = _domain_id
          AND c.id = id_cont; 
      
      INSERT INTO history.contact_attribute(
        id,
        attribute_id,
        attribute_type_id,
        contact_id,
        value)
        SELECT 
          ca.id,
          ca.attribute_id,
          ca.attribute_type_id,
          id_cont,
          ca.value  
        FROM history.domain_contact dc
        JOIN ONLY domain_contact dc2 ON dc2.id = dc.id
        JOIN ONLY contact_attribute ca ON dc2.contact_id = ca.contact_id 
        WHERE dc.domain_id = _domain_id 
          AND dc.contact_id = id_cont;

    END LOOP; 
  END IF; 

  RAISE NOTICE 'starting to work on host'; 

  -- 3. add record to host
  WITH inserted AS (
    INSERT INTO history.host(  
    orig_id,
    tenant_customer_id,
    name,
    domain_id,
    tags,
    metadata)
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
  RETURNING id 
  )SELECT array_agg(id) INTO _id_host FROM inserted;

  IF _id_host IS NOT NULL THEN
  
    FOREACH id_host IN ARRAY _id_host
    LOOP
      RAISE NOTICE 'id_host %', id_host; 

      INSERT INTO history.domain_host( 
        id,
        domain_id,
        host_id)
        SELECT 
          dh.id,
          dh.domain_id,
          id_host
        FROM domain_host dh 
        JOIN history.host h ON h.orig_id = dh.host_id
        WHERE dh.domain_id = _domain_id
          AND h.id = id_host;

      INSERT INTO history.host_addr (
        id,
        host_id,
        address)
        SELECT 
          ha.id,
          id_host,
          ha.address
        FROM domain_host dh
        JOIN history.host h ON h.orig_id = dh.host_id 
        JOIN ONLY host_addr ha ON h.orig_id = ha.host_id 
        WHERE dh.domain_id = _domain_id
          AND h.id = id_host;
    END LOOP; 
  END IF; 

  -- 4. add record to dns
  WITH inserted AS (
    INSERT INTO history.secdns_key_data(
      id,
      flags,
      protocol,
      algorithm,
      public_key)
      SELECT 
        skd.id,
        skd.flags,
        skd.protocol,
        skd.algorithm,
        skd.public_key
      FROM domain_secdns ds 
      JOIN ONLY secdns_key_data skd ON skd.id = ds.key_data_id
      WHERE ds.domain_id = _domain_id
    RETURNING id 
  )SELECT array_agg(id) INTO _id_dns FROM inserted;
  
  IF _id_dns IS NOT NULL THEN
    FOREACH id_dns IN ARRAY _id_dns 
    LOOP
      RAISE NOTICE 'id_dns %', id_dns;

      INSERT INTO history.domain_secdns( 
        id,
        domain_id,
        ds_data_id,
        key_data_id)
        SELECT 
          ds.id,
          ds.domain_id,
          ds.ds_data_id,
          ds.key_data_id
        FROM domain_secdns ds 
        WHERE ds.domain_id = _domain_id
          AND ds.key_data_id = id_dns;
    END LOOP; 
  END IF; 

  WITH inserted AS ( 
    INSERT INTO history.secdns_ds_data(
      id,
      key_tag,
      algorithm,
      digest_type,
      digest,
      key_data_id)
      SELECT 
        sdd.id,
        sdd.key_tag,
        sdd.algorithm,
        sdd.digest_type,
        sdd.digest,
        sdd.key_data_id
      FROM domain_secdns ds 
      JOIN ONLY secdns_ds_data sdd ON sdd.key_data_id = ds.key_data_id
      WHERE ds.domain_id = _domain_id
    RETURNING id 
  )SELECT array_agg(id) INTO _id_dns2 FROM inserted;

  IF _id_dns2 IS NOT NULL THEN
    FOREACH id_dns2 IN ARRAY _id_dns2 
    LOOP
      RAISE NOTICE 'id_dns2 %', id_dns2;

      INSERT INTO history.domain_secdns( 
        id,
        domain_id,
        ds_data_id,
        key_data_id)
        SELECT 
          ds.id,
          ds.domain_id,
          ds.ds_data_id,
          ds.key_data_id
        FROM domain_secdns ds 
        WHERE ds.domain_id = _domain_id
          AND ds.ds_data_id = id_dns2;
    END LOOP; 
  END IF;

  -- 5 delete decord from domain; information will be deleted on cascade from related 8 tables;  
  DELETE FROM domain 
  WHERE domain.id = _domain_id;

END;
$$ LANGUAGE plpgsql; 

COMMENT ON COLUMN history.host.orig_id IS '
This is original_id from host table; For tables with ids that can be used multiple times - contact.
';

COMMENT ON COLUMN history.contact_postal.orig_id IS '
This is original_id from contact_postal table; For tables with ids that can be used multiple times - contact.
';

COMMENT ON COLUMN history.contact.orig_id IS '
This is original_id from contact table; For tables with ids that can be used multiple times - contact.
';

COMMENT ON COLUMN history.domain.reason IS '
This is the reason to delete domain from the system: deletion or transfer_away. It is nullable.
Record can be Deleted or Transfered. 
';