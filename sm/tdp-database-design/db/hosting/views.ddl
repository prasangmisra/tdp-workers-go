--
-- table: v_hosting
-- description: view to list all hosting without records in child tables
-- used by reporting tool

CREATE OR REPLACE VIEW v_hosting AS
SELECT
    h.*,
    tc_name_from_id('hosting_status', h.hosting_status_id) AS status
FROM ONLY hosting h;
