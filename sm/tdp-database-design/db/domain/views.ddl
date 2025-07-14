--
-- view: v_domain_lock
-- description: this view provides domains lock details
-- can potentially be used to aggregate locks from various sources


CREATE OR REPLACE VIEW v_domain_lock AS
SELECT
    dl.id,
    dl.domain_id,
    lt.name AS name,
    dl.is_internal,
    dl.created_date,
    dl.expiry_date
FROM domain_lock dl
JOIN lock_type lt ON lt.id = dl.type_id;

--
-- view: v_domain
-- description: this view provides extended domain details
--
-- rgp_status: latest, not expired domain registry grace period status
--

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
