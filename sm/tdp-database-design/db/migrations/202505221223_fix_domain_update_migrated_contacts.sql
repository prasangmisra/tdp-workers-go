ALTER TABLE IF EXISTS update_domain_add_contact
DROP CONSTRAINT IF EXISTS update_domain_add_contact_order_contact_id_fkey;

ALTER TABLE IF EXISTS update_domain_rem_contact
DROP CONSTRAINT IF EXISTS update_domain_rem_contact_order_contact_id_fkey;

CREATE OR REPLACE FUNCTION gen_short_id() RETURNS TEXT AS $$
DECLARE
    allowed_chars text := '0123456789abcdefghijklmnopqrstuvwxyz+.-/';
    result text := '';
    bytes bytea := gen_random_bytes(32);
    i int := 0;
BEGIN
    FOR i IN 1..16 LOOP
            -- Concatenate a character from 'allowed_chars' based on the current byte.
            -- 'get_byte' function extracts the byte at position 'i' from 'bytes'.
            -- 'substr' function selects a character from 'allowed_chars' based on the byte value.
            result := result || substr(allowed_chars, (get_byte(bytes, i) % length(allowed_chars)) + 1, 1);
        END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;
