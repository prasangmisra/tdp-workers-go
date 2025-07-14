ALTER TABLE migration ADD COLUMN IF NOT EXISTS version_number TEXT NOT NULL
    DEFAULT 'v0.0.0'
    CONSTRAINT valid_version_format CHECK (version_number ~ '^v[0-9]+\.[0-9]+\.[0-9]+$');


CREATE OR REPLACE VIEW v_migration AS
SELECT
    m.version_number,
    COUNT(m.version_number) AS total_migrations,
    STRING_AGG(m.name, ', ' ORDER BY m.applied_date) AS migration_names,
    MIN(m.applied_date) AS first_migration_date,
    MAX(m.applied_date) AS last_migration_date
FROM
    migration m
GROUP BY
    m.version_number
ORDER BY
    MAX(m.applied_date) DESC;
