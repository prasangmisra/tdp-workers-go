CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- function: gen_short_id()
-- description: This function generates a unique, random string of length 16 characters
-- using a subset of alphanumeric characters and some special characters.
CREATE OR REPLACE FUNCTION gen_short_id() RETURNS TEXT AS $$
DECLARE
    allowed_chars text := '0123456789abcdefghijklmnopqrstuvwxyz+.-/=';
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

ALTER TABLE contact
    ADD COLUMN IF NOT EXISTS short_id TEXT NOT NULL UNIQUE DEFAULT gen_short_id(),
    ADD CONSTRAINT contact_short_id_length_check CHECK (char_length(short_id) >= 3 AND char_length(short_id) <= 16);


CREATE OR REPLACE FUNCTION set_contact_id_from_short_id() RETURNS TRIGGER AS $$
DECLARE
    _c_id uuid;
BEGIN
    SELECT id INTO _c_id FROM contact WHERE short_id=NEW.short_id;
    NEW.contact_id = _c_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE order_item_delete_contact
    ADD COLUMN IF NOT EXISTS short_id TEXT REFERENCES contact(short_id);

CREATE OR REPLACE TRIGGER a_set_contact_id_from_short_id_tg
    BEFORE INSERT ON order_item_delete_contact
    FOR EACH ROW WHEN (
        NEW.contact_id IS NULL AND
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE set_contact_id_from_short_id();

DROP TRIGGER IF EXISTS a_order_prevent_contact_in_use_tg ON order_item_delete_contact;

CREATE OR REPLACE TRIGGER b_order_prevent_contact_in_use_tg
    BEFORE INSERT ON order_item_delete_contact
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_contact_in_use();

ALTER TABLE order_item_update_contact
    ADD COLUMN IF NOT EXISTS short_id TEXT REFERENCES contact(short_id);

CREATE OR REPLACE TRIGGER a_set_contact_id_from_short_id_tg
    BEFORE INSERT ON order_item_update_contact
    FOR EACH ROW WHEN (
        NEW.contact_id IS NULL AND
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE set_contact_id_from_short_id();


CREATE OR REPLACE FUNCTION set_order_contact_id_from_short_id() RETURNS TRIGGER AS $$
DECLARE
    _c_id uuid;
BEGIN
    SELECT id INTO _c_id FROM contact WHERE short_id=NEW.short_id;
    NEW.order_contact_id = _c_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE update_domain_contact
    ADD COLUMN IF NOT EXISTS short_id TEXT;

CREATE OR REPLACE TRIGGER a_set_order_contact_id_from_short_id_tg
    BEFORE INSERT ON update_domain_contact
    FOR EACH ROW WHEN (
        NEW.order_contact_id IS NULL AND
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE set_order_contact_id_from_short_id();

ALTER TABLE create_domain_contact
    ADD COLUMN IF NOT EXISTS short_id TEXT;

CREATE OR REPLACE TRIGGER a_set_order_contact_id_from_short_id_tg
    BEFORE INSERT ON create_domain_contact
    FOR EACH ROW WHEN (
        NEW.order_contact_id IS NULL AND
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE set_order_contact_id_from_short_id();
