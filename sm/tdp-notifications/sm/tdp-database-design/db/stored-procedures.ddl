CREATE OR REPLACE FUNCTION shortname_ok (name TEXT) RETURNS BOOLEAN AS $$
BEGIN
  RETURN (name ~ E'^[\\w\\.\\-\\_\\+]+\\w+$');
END;
$$ LANGUAGE plpgsql;

--
-- function null_to_value(TEXT) handles NULL to be used in GiST indexes
--

-- CREATE FUNCTION null_to_value(TEXT) 
-- RETURNS TEXT AS $$
--    SELECT COALESCE($1, '');
-- $$ LANGUAGE SQL STRICT IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION null_to_value(uuid)
RETURNS uuid AS $$
BEGIN
    RETURN COALESCE($1, '00000000-0000-0000-0000-000000000000'::uuid);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 
-- function bool_to_value(BOOLEAN) handles BOOLEAN to be used in GiST indexes
--

CREATE OR REPLACE FUNCTION bool_to_value(BOOLEAN) RETURNS TEXT AS $$
SELECT CASE 
            WHEN $1 
                THEN 0 
                ELSE 1 
        END;
$$ LANGUAGE SQL STRICT IMMUTABLE SECURITY DEFINER;

