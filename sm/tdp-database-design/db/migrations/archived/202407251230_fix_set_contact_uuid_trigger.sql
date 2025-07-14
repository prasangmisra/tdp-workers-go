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

CREATE OR REPLACE FUNCTION set_order_contact_id_from_short_id() RETURNS TRIGGER AS $$
DECLARE
    _c_id uuid;
BEGIN
    SELECT id INTO _c_id FROM contact WHERE short_id=NEW.short_id AND deleted_date IS NULL;
    NEW.order_contact_id = _c_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'contact does not exists' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
