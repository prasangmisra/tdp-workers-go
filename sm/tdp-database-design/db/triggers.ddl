-- Ensure tables that have soft delete are updated automatically. Add an index
-- to speed up lookup of "alive" records.
DO $$
DECLARE
    v_stmt text;
    v_table RECORD;
    v_view text;
    v_clause text;
BEGIN
    FOR v_table IN SELECT DISTINCT
        t.tablename
    FROM
        pg_catalog.pg_tables t,
        pg_catalog.pg_attribute att,
        pg_catalog.pg_type type
    WHERE
        att.attrelid = type.typrelid
        AND type.typname = t.tablename
        AND t.tableowner = CURRENT_USER
        AND t.schemaname = CURRENT_SCHEMA
        AND att.attname = 'deleted_by'
        AND t.tablename <> 'soft_delete' LOOP
            v_stmt := 'DROP TRIGGER IF EXISTS zz_50_sofdel_' || v_table.tablename
            || ' ON "' || v_table.tablename || '";';
            EXECUTE v_stmt;
            v_stmt := 'CREATE TRIGGER zz_50_sofdel_' || v_table.tablename
                   || ' BEFORE DELETE ON "' || v_table.tablename
                   || '" FOR EACH ROW WHEN ( NOT is_data_migration() ) EXECUTE PROCEDURE soft_delete();';          
            EXECUTE v_stmt;
        END LOOP;
    FOR v_table IN
    SELECT
        cl.relname AS table_name,
        string_agg(a.attname, '_') AS columns_u,
        string_agg(a.attname, ',') AS columns_c
    FROM
        pg_constraint c
        JOIN pg_attribute a ON c.contype IN ('p')
            AND a.attrelid = c.conrelid
        JOIN pg_class cl ON cl.oid = c.conrelid
            AND c.conkey @> ARRAY[a.attnum::smallint]
            AND cl.relname !~ '^_'
        JOIN pg_namespace n ON n.nspname IN ('public')
            AND n.oid = cl.relnamespace
    WHERE
        EXISTS (
            SELECT
                TRUE
            FROM
                pg_attribute adb
            WHERE
                adb.attrelid = c.conrelid
                AND adb.attname IN ('deleted_by'))
    GROUP BY
        1 LOOP
            EXECUTE FORMAT($F$
                    CREATE UNIQUE INDEX IF NOT EXISTS %1$s_alive_%2$s_unique
                    ON %4$s(%3$s)
                    WHERE deleted_by IS NULL;
                $F$,
                v_table.table_name,
                v_table.columns_u,
                v_table.columns_c,
                quote_ident(v_table.table_name)
            );
        END LOOP;
END;
$$;

-- Ensure tables that inherit from _audit_trail are updated automatically
DO $$
DECLARE
    v_stmt text;
    v_table RECORD;
BEGIN
    FOR v_table IN SELECT DISTINCT
        t.tablename
    FROM
        pg_catalog.pg_tables t,
        pg_catalog.pg_attribute att,
        pg_catalog.pg_type type
    WHERE
        att.attrelid = type.typrelid
        AND type.typname = t.tablename
        AND t.tableowner = CURRENT_USER
        AND t.schemaname = CURRENT_SCHEMA
        AND t.tablename !~ '^audit_trail_log'
        AND EXISTS (
                SELECT
                FROM
                    pg_catalog.pg_inherits
                WHERE
                    inhparent = 'class.audit_trail'::regclass
                    AND inhrelid = att.attrelid
            )
            LOOP
                -- Setup triggers to automatically set updated by/date fields
                v_stmt := 'DROP TRIGGER IF EXISTS zz_50_audit_' || v_table.tablename
                        || ' ON "' || v_table.tablename || '";';
                EXECUTE v_stmt;
                v_stmt := 'CREATE TRIGGER zz_50_audit_' || v_table.tablename
                       || ' BEFORE UPDATE ON "' || v_table.tablename
                       || '" FOR EACH ROW EXECUTE PROCEDURE update_audit_info();';
                EXECUTE v_stmt;
                -- See if the relation includes an "id" field
                PERFORM
                    att.attnum
                FROM
                    pg_catalog.pg_class c
                    JOIN pg_catalog.pg_attribute att ON c.oid = att.attrelid
                WHERE
                    c.relname = v_table.tablename
                    AND att.attname = 'id';
                IF FOUND THEN
                    -- Setup the trigger to create an audit trail of table changes.
                    v_stmt := 'DROP TRIGGER IF EXISTS zz_60_trail_' || v_table.tablename
                           || ' ON "' || v_table.tablename || '";';
                    EXECUTE v_stmt;
                    v_stmt := 'CREATE TRIGGER zz_60_trail_' || v_table.tablename
                           || ' AFTER INSERT OR DELETE OR UPDATE ON "' || v_table.tablename
                           || '" FOR EACH ROW  WHEN ( NOT is_data_migration() ) EXECUTE PROCEDURE maintain_audit_trail();';
                    EXECUTE v_stmt;
                END IF;
            END LOOP;
END;
$$;

