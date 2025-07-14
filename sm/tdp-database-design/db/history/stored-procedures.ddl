-- 
-- function: irreversibly_delete_data()
-- description: permanently deletes data from the archive after the requared period of storage 
-- initiates by cron job 
CREATE OR REPLACE FUNCTION irreversibly_delete_data()
RETURNS VOID AS $$
BEGIN

  DELETE FROM history.domain 
  WHERE created_at < NOW() - INTERVAL '18 months';

END; 
$$ LANGUAGE plpgsql;