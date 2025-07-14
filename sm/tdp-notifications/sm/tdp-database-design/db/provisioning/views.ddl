
CREATE OR REPLACE VIEW v_provision_domain AS 
SELECT
  pd.id,
  pd.accreditation_id,
  a.name as accreditation_name,
  pd.tenant_customer_id, 
  pd.domain_name AS domain_name,
  pd.ry_cltrid,
  pd.status_id,
  'provision_domain' AS reference_table
FROM provision_domain pd
JOIN accreditation a ON a.id = pd.accreditation_id
  
  UNION

SELECT
  pdu.id,
  pdu.accreditation_id,
  a.name as accreditation_name,
  pdu.tenant_customer_id,
  pdu.domain_name AS domain_name,
  pdu.ry_cltrid,
  pdu.status_id,
  'provision_domain_update' AS reference_table
FROM provision_domain_update pdu
JOIN accreditation a ON a.id = pdu.accreditation_id

  UNION

SELECT
  pdd.id,
  pdd.accreditation_id,
  a.name as accreditation_name,
  pdd.tenant_customer_id,
  pdd.domain_name AS domain_name,
  pdd.ry_cltrid,
  pdd.status_id,
  'provision_domain_delete' AS reference_table
FROM provision_domain_delete pdd
JOIN accreditation a ON a.id = pdd.accreditation_id

  UNION

SELECT
  pdr.id,
  pdr.accreditation_id,
  a.name as accreditation_name,
  pdr.tenant_customer_id,
  pdr.domain_name AS domain_name,
  pdr.ry_cltrid,
  pdr.status_id,
  'provision_domain_renew' AS reference_table
FROM provision_domain_renew pdr
JOIN accreditation a ON a.id = pdr.accreditation_id

  UNION

SELECT
  pdr.id,
  pdr.accreditation_id,
  a.name as accreditation_name,
  pdr.tenant_customer_id,
  pdr.domain_name AS domain_name,
  pdr.ry_cltrid,
  pdr.status_id,
  'provision_domain_redeem' AS reference_table
FROM provision_domain_redeem pdr
JOIN accreditation a ON a.id = pdr.accreditation_id;

CREATE TRIGGER v_provision_domain_tg INSTEAD OF UPDATE ON v_provision_domain
    FOR EACH ROW EXECUTE PROCEDURE provision_status_update();
