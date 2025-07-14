-- Adding session_max_sec column to epp settings to allow for adaptation
-- to registries with varying session lifetimes.

ALTER TABLE class.epp_setting ADD COLUMN IF NOT EXISTS session_max_sec INT;

COMMENT ON column class.epp_setting.session_max_sec IS 'number of seconds until session expires and reconnection required. NULL represents no limit.';

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
    COALESCE(ae.xml_verify_schema,pie.xml_verify_schema,TRUE) AS xml_verify_schema,
    COALESCE(ae.keepalive_seconds,pie.keepalive_seconds) AS keepalive_seconds,
    COALESCE(ae.session_max_cmd,pie.session_max_cmd) AS session_max_cmd,
    COALESCE(ae.session_max_sec,pie.session_max_sec) AS session_max_sec
FROM accreditation_epp ae 
    JOIN accreditation a ON a.id = ae.accreditation_id
    JOIN tenant t ON t.id=a.tenant_id
    JOIN provider_instance pi ON pi.id=a.provider_instance_id
    JOIN provider_instance_epp pie ON pie.provider_instance_id = a.provider_instance_id 
    JOIN provider p ON p.id = pi.provider_id;