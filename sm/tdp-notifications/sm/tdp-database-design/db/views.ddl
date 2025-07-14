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

-- views live here
