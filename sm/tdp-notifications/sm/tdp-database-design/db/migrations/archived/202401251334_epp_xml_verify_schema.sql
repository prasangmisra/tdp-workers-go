-- Adding xml_verify_schema column to epp settings to allow disabling verification
-- on selected accreditations or provider instances

ALTER TABLE class.epp_setting ADD COLUMN IF NOT EXISTS xml_verify_schema BOOLEAN;

COMMENT ON column class.epp_setting.xml_verify_schema IS 'whether to use XSD schema for XML verification';

CREATE OR REPLACE VIEW v_accreditation_epp AS 
SELECT 
    t.name AS tenant_name,
    t.id   AS tenant_id,
    p.id   AS provider_id,
    p.name AS provider_name,
    a.name AS accreditation_name,
    a.id   AS accreditation_id,
    ae.id  AS accreditation_epp_id,
    ae.cert_id,
    ae.clid,
    ae.pw,
    COALESCE(ae.host,pie.host) AS host,
    COALESCE(ae.port,pie.port) AS port,
    COALESCE(ae.conn_min,pie.conn_min) AS conn_min,
    COALESCE(ae.conn_max,pie.conn_max) AS conn_max,
    COALESCE(ae.ssl_verify_host,pie.ssl_verify_host,TRUE) AS ssl_verify_host,
    COALESCE(ae.xml_verify_schema,pie.xml_verify_schema,TRUE) AS xml_verify_schema
FROM accreditation_epp ae 
    JOIN accreditation a ON a.id = ae.accreditation_id
    JOIN tenant t ON t.id=a.tenant_id
    JOIN provider_instance pi ON pi.id=a.provider_instance_id
    JOIN provider_instance_epp pie ON pie.provider_instance_id = a.provider_instance_id 
    JOIN provider p ON p.id = pi.provider_id;
