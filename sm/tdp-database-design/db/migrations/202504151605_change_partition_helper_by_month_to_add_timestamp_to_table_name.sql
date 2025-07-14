CREATE OR REPLACE FUNCTION partition_helper_by_month(_table TEXT) RETURNS BOOLEAN AS
$$
DECLARE
  _dates RECORD;
  _stmt TEXT;
  _table_exists BOOLEAN DEFAULT FALSE;
BEGIN
  -- Normalize table name to lowercase
  _table := LOWER(_table);

  -- Generate partitions for the current month and the next three months
  FOR _dates IN SELECT
                    FORMAT('%s_%s', _table, TO_CHAR(generate_series, 'YYYYMM')) AS table_name, -- Use YYYYMM for table names
                    TO_CHAR(generate_series, 'YYYY-MM-DD HH24:MI:SSOF') AS from_timestamp,       -- Include full timestamp
                    TO_CHAR(generate_series + '1 month'::INTERVAL, 'YYYY-MM-DD HH24:MI:SSOF') AS to_timestamp
                FROM generate_series(
                        DATE_TRUNC('month', clock_timestamp() AT TIME ZONE 'UTC'),
                        DATE_TRUNC('month', clock_timestamp() AT TIME ZONE 'UTC' + '3 month'::INTERVAL),
                        '1 month'::INTERVAL
                      )
  LOOP
    -- Check if the partition table already exists
    SELECT EXISTS INTO _table_exists (
        SELECT FROM
          pg_tables
        WHERE
          schemaname = 'public' AND
          tablename = _dates.table_name
    );

    -- Create the partition if it doesn't exist
    IF NOT _table_exists THEN
      _stmt := FORMAT(
        'CREATE TABLE %1$s PARTITION OF %2$s FOR VALUES FROM (%3$s) TO (%4$s)',
        _dates.table_name,
        _table,
        QUOTE_LITERAL(_dates.from_timestamp),
        QUOTE_LITERAL(_dates.to_timestamp)
      );
      EXECUTE _stmt;
    ELSE
      -- Log a notice if the partition already exists
      RAISE NOTICE 'Skipping % (partition of %) since it already exists', _dates.table_name, _table;
    END IF;
  END LOOP;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
