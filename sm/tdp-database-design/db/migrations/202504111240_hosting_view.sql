--
-- table: v_hosting
-- description: view to list all hosting without records in child tables
-- used by reporting tool

CREATE OR REPLACE VIEW v_hosting AS
    SELECT 
        h.*
    FROM ONLY hosting h;
