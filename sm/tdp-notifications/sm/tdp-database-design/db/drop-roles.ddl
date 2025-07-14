-- This is -*- sql -*-
--
-- Discard the roles before dropping the database.

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM tucows;
