BEGIN;

-- This will DROP all associated triggers as well

DROP FUNCTION IF EXISTS force_hosting_status_id_from_name CASCADE;
DROP FUNCTION IF EXISTS force_hosting_status_name_from_id CASCADE;

-------------------------------------- hosting and v_hosting ----------------------------------------
DROP VIEW IF EXISTS v_hosting;

-- drop status column
ALTER TABLE hosting
DROP COLUMN IF EXISTS status;

CREATE VIEW v_hosting AS
SELECT
    h.*,
    tc_name_from_id('hosting_status', h.hosting_status_id) AS status
FROM ONLY hosting h;
------------------------------ provision_hosting_create --------------------------------

-- drop status column
ALTER TABLE provision_hosting_create
DROP COLUMN IF EXISTS status;

------------------------------ provision_hosting_delete --------------------------------

-- drop status column
ALTER TABLE provision_hosting_delete
DROP COLUMN IF EXISTS status;

------------------------------ provision_hosting_update --------------------------------

-- drop status column
ALTER TABLE provision_hosting_update
DROP COLUMN IF EXISTS status;

COMMIT;
