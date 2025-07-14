-- for any table inheriting from the _provision table, this will automatically
-- ensure that the triggers are set.
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
        AND EXISTS (
            SELECT
            FROM
                pg_catalog.pg_inherits
            WHERE
                inhparent = 'class.provision'::regclass
                AND inhrelid = att.attrelid)
            LOOP
                -- Setup triggers to aumatically update the order_item_plan
                v_stmt := 'DROP TRIGGER IF EXISTS __auto__provision_finish_tg' || v_table.tablename
                        || ' ON "' || v_table.tablename || '";';
                EXECUTE v_stmt;
                v_stmt := 'CREATE TRIGGER __auto__provision_finish_tg' || v_table.tablename
                       || ' AFTER UPDATE ON "' || v_table.tablename || '" '
                       || ' FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id) '
                       || ' EXECUTE PROCEDURE provision_finish();';
                EXECUTE v_stmt;
                -- Setup triggers to either delete or add the provisioned_date
                v_stmt := 'DROP TRIGGER IF EXISTS __auto__provision_cleanup_tg' || v_table.tablename
                       || ' ON "' || v_table.tablename || '";';
                EXECUTE v_stmt;
                v_stmt := 'CREATE TRIGGER __auto__provision_cleanup_tg' || v_table.tablename
                       || ' AFTER UPDATE ON "' || v_table.tablename || '" '
                       || ' FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id) '
                       || ' EXECUTE PROCEDURE provision_cleanup();';
                EXECUTE v_stmt;
                v_stmt := 'ALTER TABLE ' || v_table.tablename
                       || ' DROP CONSTRAINT IF EXISTS status_id_fk';
                EXECUTE v_stmt;
                v_stmt := 'ALTER TABLE ' || v_table.tablename
                       || ' ADD CONSTRAINT status_id_fk FOREIGN KEY (status_id) REFERENCES provision_status';
                EXECUTE v_stmt;
            END LOOP;
END;
$$;

