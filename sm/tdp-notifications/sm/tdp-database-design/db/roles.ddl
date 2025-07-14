-- This is the GROUP where all the normal users should belong --
-- DROP ROLE IF EXISTS tucows_billing_user;

DO $$
BEGIN
  CREATE ROLE tucows_user
    WITH NOSUPERUSER NOREPLICATION NOCREATEROLE NOCREATEDB;
  EXCEPTION WHEN duplicate_object THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;
END
$$;

COMMENT ON ROLE tucows_user IS 'Group for normal users of the system.';

-- REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM tucows_billing_user;
