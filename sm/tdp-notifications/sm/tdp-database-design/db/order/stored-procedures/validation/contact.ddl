-- function: set_contact_id_from_short_id()
-- description: set contact_id from short_id
CREATE OR REPLACE FUNCTION set_contact_id_from_short_id() RETURNS TRIGGER AS $$
DECLARE
    _c_id uuid;
BEGIN
    SELECT id INTO _c_id FROM ONLY contact WHERE short_id=NEW.short_id AND deleted_date IS NULL;
    NEW.contact_id = _c_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'contact does not exists' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_prevent_contact_domain_associated()
-- description: check if contact is associated with any domain
CREATE OR REPLACE FUNCTION order_prevent_contact_in_use() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM ONLY domain_contact WHERE contact_id=NEW.contact_id;

    IF FOUND THEN
        RAISE EXCEPTION 'cannot delete contact: in use.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
