CREATE OR REPLACE FUNCTION tc_gen_password(v_length INT) RETURNS TEXT AS
$$
DECLARE
  v_iter    INT;
  pw        TEXT DEFAULT '';
  v_ch      CHAR;
BEGIN

  FOR v_iter IN 1..v_length LOOP
    SELECT CHR(generate_series) INTO v_ch AS c FROM generate_series(33,127,1) ORDER BY RANDOM() LIMIT 1;
    pw = pw || v_ch;
  END LOOP;

  RETURN pw;

END;
$$ LANGUAGE plpgsql;

--
-- Merges two JSONB objects, with keys from merge object overwriting the
-- keys from the original object.
--
CREATE OR REPLACE FUNCTION tc_json_merge(original JSONB, merge JSONB) RETURNS JSONB AS $$
DECLARE
  return_json JSON;
BEGIN

  -- NOTE: PG 9.5+ have methods that can do this directly, but we are on 9.4
  SELECT json_object_agg(j.key, j.value) INTO return_json
  FROM (
    WITH to_merge AS (
      SELECT * FROM json_each(merge::JSON)
    )
    SELECT * FROM json_each(original::JSON)
    WHERE key NOT IN (SELECT key FROM to_merge)
    UNION ALL
    SELECT * FROM to_merge
  ) j;
  RETURN return_json::JSONB;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION tc_json_merge(JSONB, JSONB) IS '

This function merges two JSONB objects, with keys from the merge object
overwriting the keys from the original object.

';

--
-- Converts a JSONB array to an array of text elements
-- Derived from: https://dba.stackexchange.com/questions/54283/how-to-turn-json-array-into-postgres-array
--
CREATE OR REPLACE FUNCTION jsonb_array_to_text_array(p_js JSONB)
  RETURNS TEXT[]
  LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
RETURN
  CASE p_js
    WHEN 'null'::JSONB THEN
      NULL
    ELSE
      ARRAY(SELECT jsonb_array_elements_text(p_js))
    END;

--
-- Check for null or ascii text
--
CREATE OR REPLACE FUNCTION is_null_or_ascii(p_t TEXT)
  RETURNS BOOLEAN
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN
  (p_t IS NULL OR p_t ~ '^[ -~]*$');

--
-- This function is used to update the updated_date and updated_by
-- fields in the tables that inherit from _audit.
--
CREATE OR REPLACE FUNCTION update_audit_info() RETURNS TRIGGER AS $$
BEGIN

  NEW.updated_date := NOW();
  NEW.updated_by   := CURRENT_USER;
  RETURN NEW;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_audit_info() IS '

This function is used to update the updated_date and updated_by
fields in the tables that inherit from _audit.

';

CREATE OR REPLACE FUNCTION maintain_audit_trail() RETURNS trigger AS
$$
DECLARE
    v_table TEXT;
    v_hnew hstore;
    v_hold hstore;
    v_changes hstore;
    v_id UUID;
BEGIN
    -- Get base table name for partitioned tables
    v_table := regexp_replace(TG_TABLE_NAME, '_[0-9]{6}$', '');

    CASE TG_OP
        WHEN 'INSERT' THEN
            v_hnew := hstore(NEW);
            -- Get ID if it exists, otherwise NULL
            v_id := (v_hnew->'id')::uuid;

            INSERT INTO audit_trail_log (
                created_by,
                table_name,
                operation,
                object_id,
                new_value,
                statement_date
            ) VALUES (
                     current_user,
                     v_table,
                     TG_OP,
                     v_id,
                     v_hnew,
                     clock_timestamp()
                     );
            RETURN NEW;

        WHEN 'DELETE' THEN
            v_hold := hstore(OLD);
            -- Get ID if it exists, otherwise NULL
            v_id := (v_hold->'id')::uuid;

            INSERT INTO audit_trail_log (
                created_by,
                table_name,
                operation,
                object_id,
                old_value,
                statement_date
            ) VALUES (
                     current_user,
                     v_table,
                     TG_OP,
                     v_id,
                     v_hold,
                     clock_timestamp()
                     );
            RETURN OLD;

        WHEN 'UPDATE' THEN
            v_hold := hstore(OLD);
            v_hnew := hstore(NEW);
            -- Get ID if it exists, otherwise NULL
            v_id := (v_hnew->'id')::uuid;

            -- Calculate changes
            v_changes := v_hnew - v_hold;

            -- Only log if there are non-update-timestamp changes
            IF v_changes != ''::hstore AND
               EXISTS (
                   SELECT 1
                   FROM EACH(v_changes) AS t(k,v)
                   WHERE k !~* '^updated_'
               ) THEN
                INSERT INTO audit_trail_log (
                    created_by,
                    table_name,
                    operation,
                    object_id,
                    old_value,
                    new_value,
                    statement_date
                ) VALUES (
                         current_user,
                         v_table,
                         TG_OP,
                         v_id,
                         v_hold,
                         v_changes,
                         clock_timestamp()
                         );
            END IF;
            RETURN NEW;
        END CASE;
END;
$$
    LANGUAGE plpgsql;

COMMENT ON FUNCTION maintain_audit_trail() IS '
This function keeps track of modifications made to an audit
table. It stores the previous values and new values. For first insert it
stores all values.
';

-- prevent record from being deleted --

CREATE OR REPLACE FUNCTION soft_delete() RETURNS TRIGGER AS $$
BEGIN

  EXECUTE 'UPDATE ' || TG_TABLE_NAME || ' SET deleted_date = NOW(), deleted_by = $1 WHERE id = $2'
  USING CURRENT_USER, OLD.id;
  RETURN NULL;

END;
$$ LANGUAGE plpgsql;


-- tc_record_from_name(table_name TEXT, name TEXT)
--       This function returns a RECORD representing a row from a table
--       that has a name of "name"
--
CREATE OR REPLACE FUNCTION tc_record_from_name(table_name TEXT, name TEXT) RETURNS RECORD AS $$
DECLARE
  _result RECORD;
BEGIN

  EXECUTE 'SELECT * FROM '|| table_name ||' WHERE name = $1' INTO STRICT _result
    USING name;
  RETURN _result;

END;
$$ LANGUAGE plpgsql;


-- tc_record_from_id(table_name TEXT, id UUID)
--       This function returns a RECORD representing a row from a table
--       that has an id matching the given value
--
CREATE OR REPLACE FUNCTION tc_record_from_id(table_name TEXT, id UUID) RETURNS RECORD AS $$
DECLARE
  _result RECORD;
BEGIN

  EXECUTE 'SELECT * FROM '|| table_name ||' WHERE id = $1' INTO STRICT _result
    USING id;
  RETURN _result;

END;
$$ LANGUAGE plpgsql;


-- tc_id_from_name(table_name TEXT, name TEXT)
--       This function returns an UUID representing a row ID from a table
--       that has a name of "name"
--
CREATE OR REPLACE FUNCTION tc_id_from_name(table_name TEXT, name TEXT) RETURNS UUID AS $$
DECLARE
  _result UUID;
BEGIN

  EXECUTE 'SELECT id FROM '|| table_name ||' WHERE name = $1' INTO STRICT _result
    USING name;
  RETURN _result;

END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- tc_order_type_id_from_name(order_type TEXT, product TEXT)
--       This function returns the order_type_id for a given order_type and product
--
CREATE OR REPLACE FUNCTION tc_order_type_id_from_name(order_type TEXT, product TEXT) RETURNS UUID AS $$
DECLARE
    _result UUID;
BEGIN

    EXECUTE 'SELECT ot.id FROM order_type ot INNER JOIN product p ON ot.product_id = p.id WHERE ot.name = $1 AND p.name = $2' INTO STRICT _result
        USING order_type, product;
    RETURN _result;

END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- tc_name_from_id(table_name TEXT, id UUID)
--       This function returns TEXT representing a "name" value from a table
--       that has an id matching the given value
--
CREATE OR REPLACE FUNCTION tc_name_from_id(table_name TEXT, id UUID) RETURNS TEXT AS $$
DECLARE
  _result TEXT;
BEGIN

  EXECUTE 'SELECT name FROM '|| table_name ||' WHERE id = $1' INTO STRICT _result
    USING id;
  RETURN _result;

END;
$$ LANGUAGE plpgsql STABLE;


-- tc_descr_from_name(table_name TEXT, name TEXT)
--       This function returns TEXT representing a "descr" value from a table
--       that has a name matching the given value
--
CREATE OR REPLACE FUNCTION tc_descr_from_name(table_name TEXT, name TEXT) RETURNS TEXT AS $$
DECLARE
  _result TEXT;
BEGIN

  EXECUTE 'SELECT descr FROM '|| table_name ||' WHERE name = $1' INTO STRICT _result
    USING name;
  RETURN _result;

END;
$$ LANGUAGE plpgsql STABLE;


-- tc_descr_from_id(table_name TEXT, id UUID)
--       This function returns TEXT representing a "descr" value from a table
--       that has an id matching the given value
--
CREATE OR REPLACE FUNCTION tc_descr_from_id(table_name TEXT, id UUID) RETURNS TEXT AS $$
DECLARE
  _result TEXT;
BEGIN

  EXECUTE 'SELECT descr FROM '|| table_name ||' WHERE id = $1' INTO STRICT _result
    USING id;
  RETURN _result;

END;
$$ LANGUAGE plpgsql STABLE;


--
-- This function is used to lowercase the "name" field of a table prior
-- to INSERT or UPDATE
--
CREATE OR REPLACE FUNCTION tc_lowercase_name() RETURNS TRIGGER AS $$
BEGIN
  NEW.name := LOWER(NEW.name);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--
-- tc_tmpl(args)
--
-- given a template variable (using the {var} notation), this function will
-- iterate through the HSTORE (2nd arg) to replace variables and return
-- a TEXT that contains the resulting string:
--
-- select tc_tmpl('{name} has email {email}', 'name=>"francisco", email=>"francisco@obispo.link"');
--
--              tc_tmpl
-- -----------------------------------------
-- francisco has email francisco@obispo.link
--
-- File:    stored-procedures.ddl
--

CREATE OR REPLACE FUNCTION tc_tmpl(_t TEXT, _tmpl_var HSTORE) RETURNS TEXT AS $$
DECLARE
  _result    TEXT;
  _var       TEXT[];
  _replace   TEXT;
BEGIN

  _result := _t;

  FOR _var IN SELECT regexp_matches( _t, '{([\w_]+)}', 'g' )
  LOOP
    _replace := _tmpl_var->_var[1];

    IF _replace IS NULL THEN
      _replace := FORMAT( '{%s}', _var[1] );
    END IF;

    _result := REPLACE( _result, FORMAT( '{%s}', _var[1] ), _replace );
  END LOOP;

  RETURN _result;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION random_color() RETURNS INT[] AS
$$

  SELECT  ARRAY_AGG(a.value) FROM (
    SELECT (FLOOR(RANDOM() * (200-10 ) + 10))::INT AS value FROM generate_series(1,3)
  ) a

$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION normalize_email(_e TEXT) RETURNS TEXT AS
$$
  SELECT LOWER(TRIM(_e));
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION normalize_email_tg() RETURNS TRIGGER AS
$$
BEGIN
  NEW.email=normalize_email(NEW.email);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;



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


CREATE OR REPLACE FUNCTION cron_partition_helper_by_month() RETURNS BOOLEAN AS
$$
  DECLARE _partitioned TEXT;
  BEGIN

  FOR _partitioned IN SELECT
                        DISTINCT parent.relname
                      FROM pg_inherits
                          JOIN pg_class parent            ON pg_inherits.inhparent = parent.oid
                          JOIN pg_class child             ON pg_inherits.inhrelid   = child.oid
                          JOIN pg_namespace nmsp_parent   ON nmsp_parent.oid  = parent.relnamespace
                          JOIN pg_namespace nmsp_child    ON nmsp_child.oid   = child.relnamespace
                      WHERE child.relname ~ '_\d{6}$' AND nmsp_parent.nspname = 'public'
  LOOP

    PERFORM partition_helper_by_month(_partitioned);

  END LOOP;


  RETURN TRUE;

  END;
$$ LANGUAGE plpgsql;


-- function: tld_part
-- description: returns tld for given fqdn (domain name or hostname).
CREATE OR REPLACE FUNCTION tld_part(fqdn TEXT) RETURNS TEXT AS $$
DECLARE
  v_tld TEXT;
BEGIN
  SELECT name INTO v_tld
  FROM tld
  WHERE fqdn LIKE '%' || name
  ORDER BY LENGTH(name) DESC
  LIMIT 1;

  RETURN v_tld;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION tld_part IS 'returns the tld/apex portion of a FQDN';

-- Function: get_host_parent_domain
-- Description: Returns the domain name of a FQDN hostname and tenant_customer_id.
CREATE OR REPLACE FUNCTION get_host_parent_domain(p_host_name TEXT, p_tenant_customer_id uuid) RETURNS RECORD AS $$
DECLARE
    v_parent_domain RECORD;
    v_partial_domain TEXT;
    dot_pos INT;
BEGIN
    -- Start by checking the full host name
    v_partial_domain := p_host_name;

    LOOP
        -- Check if the current partial domain exists
        SELECT * INTO v_parent_domain
        FROM v_domain
        WHERE name = v_partial_domain
          AND tenant_customer_id = p_tenant_customer_id;

        IF FOUND THEN
            EXIT;
        END IF;

        -- Find the position of the first dot
        dot_pos := POSITION('.' IN v_partial_domain);

        -- If no more dots are found, exit the loop
        IF dot_pos = 0 THEN
            RETURN NULL;
        END IF;

        -- Trim the domain segment before the first dot
        v_partial_domain := SUBSTRING(v_partial_domain FROM dot_pos + 1);
    END LOOP;

    RETURN v_parent_domain;
END;
$$ LANGUAGE plpgsql;



-- function: domain_name_part
-- description: returns domain name part of a fqdn (domain name or hostname).
CREATE OR REPLACE FUNCTION domain_name_part(fqdn TEXT) RETURNS TEXT AS $$
DECLARE
    v_tld TEXT;
BEGIN
    v_tld := tld_part(fqdn);
    RETURN SUBSTRING(fqdn FROM 1 FOR LENGTH(fqdn) - LENGTH('.' || v_tld));
END;
$$ LANGUAGE plpgsql;

-- is_jsonb_empty_or_null(input_jsonb jsonb)
--       This function returns a boolean indicating whether the input JSONB is either null or an empty JSONB object.
--
CREATE OR REPLACE FUNCTION is_jsonb_empty_or_null(input_jsonb jsonb)
    RETURNS BOOLEAN AS $$
BEGIN
    RETURN input_jsonb IS NULL OR input_jsonb = '{}'::jsonb;
END;
$$ LANGUAGE plpgsql;


-- function: get_accreditation_tld_by_name
-- description: returns accreditation_tld record by name (domain name or hostname) for an order.
CREATE OR REPLACE FUNCTION get_accreditation_tld_by_name(fqdn TEXT, tc_id UUID) RETURNS RECORD AS $$
DECLARE
  v_tld_name    TEXT;
  v_acc_tld     RECORD;
BEGIN
    v_tld_name := tld_part(fqdn);

    SELECT v_accreditation_tld.*, tnc.id as tenant_customer_id INTO v_acc_tld
    FROM v_accreditation_tld
             JOIN tenant_customer tnc ON tnc.tenant_id= v_accreditation_tld.tenant_id
    WHERE tld_name = v_tld_name
      AND tnc.id =tc_id
      AND is_default;

    IF NOT FOUND THEN
      RETURN NULL;
    END IF;
    
    RETURN v_acc_tld;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION validate_secdns_type() RETURNS TRIGGER AS $$
DECLARE
  result INTEGER;
  domainId UUID;
BEGIN

  EXECUTE format('SELECT ($1).%I', TG_ARGV[1]) INTO domainId USING NEW;

  EXECUTE format('
    SELECT 1 FROM %I  
    WHERE %I = $1 
    AND (($2 IS NOT NULL AND ds_data_id IS NOT NULL)  
        OR ($3 IS NOT NULL AND key_data_id IS NOT NULL))', TG_ARGV[0], TG_ARGV[1]
    ) INTO result USING domainId, NEW.key_data_id, NEW.ds_data_id;

    IF result IS NOT NULL THEN
      RAISE EXCEPTION 'Cannot mix key_data_id and ds_data_id for the same domain';  
    END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.is_data_migration() RETURNS BOOLEAN AS $$
  SELECT (current_user = 'migration_user');
$$ LANGUAGE SQL  IMMUTABLE;

-- function: is_host_ipv6_supported
-- description: returns true if the host has an IPv6 address and the TLD supports IPv6.
CREATE OR REPLACE FUNCTION is_host_ipv6_supported(v_order_host_addrs INET[], v_accreditation_tld_id UUID) RETURNS BOOLEAN AS $$
BEGIN
  IF EXISTS (
      SELECT 1
      FROM UNNEST(v_order_host_addrs) AS addr
      WHERE family(addr) = 6
  ) THEN
      RETURN get_tld_setting(
          p_key => 'tld.dns.ipv6_support',
          p_accreditation_tld_id => v_accreditation_tld_id
      )::BOOLEAN;
  END IF;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- function: is_valid_regex
-- description: returns true if the input value is a valid regex.
CREATE OR REPLACE FUNCTION is_valid_regex(value TEXT) RETURNS BOOLEAN AS $$
BEGIN
  PERFORM '' ~* value;
  RETURN TRUE;
EXCEPTION
  WHEN others THEN
    RAISE EXCEPTION 'Invalid regular expression: %', value;
END;
$$ LANGUAGE plpgsql;



-- function: is_percentage
-- description: Checks if the value is a valid percentage. Must be greater than or equal to 0.
CREATE OR REPLACE FUNCTION is_percentage(value NUMERIC) RETURNS BOOLEAN AS $$
BEGIN
  IF value < 0 THEN
    RAISE EXCEPTION 'Value must be greater than or equal to 0. Value: %', value;
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
