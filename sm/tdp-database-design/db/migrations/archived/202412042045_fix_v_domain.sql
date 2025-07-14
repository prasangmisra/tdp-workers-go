DROP VIEW IF EXISTS v_domain;
CREATE OR REPLACE VIEW v_domain AS
SELECT
    d.*,
    act.accreditation_id,
    rgp.id AS rgp_status_id,
    rgp.epp_name AS rgp_epp_status,
    lock.names AS locks
FROM domain d
         JOIN accreditation_tld act ON act.id = d.accreditation_tld_id
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
    ) rgp ON rgp.expiry_date >= NOW()
         LEFT JOIN LATERAL (
    SELECT
        JSON_AGG(vdl.name) AS names
    FROM v_domain_lock vdl
    WHERE vdl.domain_id = d.id AND NOT vdl.is_internal
    ) lock ON TRUE;
