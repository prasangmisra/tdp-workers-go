-- add plus sign to ValidMbox regex and ValidLHS regex
CREATE OR REPLACE FUNCTION ValidLHS(u TEXT) RETURNS BOOLEAN AS $$
SELECT $1 ~ '^[-_a-z0-9.+^\$]{1,}$'
        AND LENGTH($1) <= 64;
$$ LANGUAGE SQL STRICT IMMUTABLE SECURITY DEFINER;

-----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ValidMbox(u TEXT) RETURNS BOOLEAN AS $$
SELECT $1 ~ '^[-_a-z0-9.+^\$]{1,}@.{1,}$'
        AND public.ValidLHS(split_part($1, '@', 1))
        AND public.ValidFQDN(split_part($1, '@', 2))
        AND split_part($1, '@', 3) = '';
$$ LANGUAGE SQL STRICT IMMUTABLE SECURITY DEFINER;
