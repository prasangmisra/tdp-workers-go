CREATE OR REPLACE FUNCTION partition_helper_by_month(_table TEXT) RETURNS BOOLEAN AS
$$
DECLARE
  _dates  RECORD;
  _stmt   TEXT;
  _table_exists   BOOLEAN DEFAULT FALSE;
BEGIN

  _table := LOWER(_table);

  FOR _dates IN SELECT
                    FORMAT('%s_%s',_table,TO_CHAR(generate_series,'YYYYMM')) AS table_name,
                    TO_CHAR(generate_series,'YYYY-MM-DD') AS from_date,
                    TO_CHAR(generate_series + '1 month'::INTERVAL,'YYYY-MM-DD') AS to_date,
                    EXTRACT(year FROM generate_series) AS from_year,
                    EXTRACT(month FROM generate_series) AS from_month
                FROM generate_series(
                        DATE_TRUNC('month', clock_timestamp() AT TIME ZONE 'UTC'),
                        DATE_TRUNC('month', clock_timestamp() AT TIME ZONE 'UTC' + '3 month'::INTERVAL),
                        '1 month'::INTERVAL
                      )
  LOOP

     SELECT EXISTS INTO _table_exists (
        SELECT FROM
          pg_tables
        WHERE
          schemaname = 'public' AND
          tablename  = _dates.table_name
    );

    IF NOT _table_exists THEN

      _stmt := FORMAT(
        'CREATE TABLE %1$s PARTITION OF %2$s FOR VALUES FROM (%3$s) TO (%4$s)',
        _dates.table_name,
        _table,
        QUOTE_LITERAL(_dates.from_date),
        QUOTE_LITERAL(_dates.to_date)
      );
      EXECUTE _stmt;
    ELSE
      RAISE NOTICE 'skipping % (partition of %) since already exists',_dates.table_name,_table;
    END IF;

  END LOOP;

  RETURN TRUE;
END;
$$
LANGUAGE plpgsql;
