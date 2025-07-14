--
-- Manage schema migrations.
--
CREATE TABLE IF NOT EXISTS migration (
    version             TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    applied_date        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE migration IS '
Record of schema migrations applied.
';

COMMENT ON COLUMN migration.version      IS 'Timestamp string of migration file in format YYYYMMDDHHMM (must match filename).';
COMMENT ON COLUMN migration.name         IS 'Name of migration from migration filename.';
COMMENT ON COLUMN migration.applied_date IS 'Postgres timestamp when migration was recorded.';
