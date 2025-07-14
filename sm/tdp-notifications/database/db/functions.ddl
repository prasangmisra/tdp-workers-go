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