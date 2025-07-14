-- function: order_prevent_if_short_id_exists()
-- description: prevent create if contact with short id already exists
CREATE OR REPLACE FUNCTION order_prevent_if_short_id_exists() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE
    FROM ONLY contact c
    WHERE c.short_id = NEW.short_id;

    IF FOUND THEN
        RAISE EXCEPTION 'contact already exists' USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER a_order_prevent_if_short_id_exists_tg
    BEFORE INSERT ON order_contact
    FOR EACH ROW WHEN (
        NEW.short_id IS NOT NULL
    )
    EXECUTE PROCEDURE order_prevent_if_short_id_exists();

CREATE OR REPLACE FUNCTION set_contact_id_from_short_id() RETURNS TRIGGER AS $$
DECLARE
    _c_id uuid;
BEGIN
    SELECT id INTO _c_id FROM ONLY contact WHERE short_id=NEW.short_id;
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
    SELECT id INTO _c_id FROM contact WHERE short_id=NEW.short_id;
    NEW.order_contact_id = _c_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'contact does not exists' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
DECLARE
    _key   text;
    _value BOOLEAN;
BEGIN

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            NEW.domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_update_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
        DO UPDATE SET contact_id = EXCLUDED.contact_id, handle = EXCLUDED.handle;

    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            NEW.domain_id,
            h.id
        FROM ONLY host h
        WHERE h.name IN (SELECT UNNEST(NEW.hosts))
          AND h.tenant_customer_id = NEW.tenant_customer_id
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete removed hosts
    DELETE FROM
        domain_host dh
        USING
            host h
    WHERE
        NEW.hosts IS NOT NULL
      AND h.name NOT IN (SELECT UNNEST(NEW.hosts))
      AND dh.domain_id = NEW.domain_id
      AND dh.host_id = h.id;

    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew),
        auth_info = COALESCE(NEW.auth_info, d.auth_info)
    WHERE d.id = NEW.domain_id;

    IF NEW.locks IS NOT NULL THEN
        FOR _key, _value IN SELECT * FROM jsonb_each_text(NEW.locks)
            LOOP
                IF _value THEN
                    INSERT INTO domain_lock(domain_id,type_id) VALUES
                        (NEW.domain_id,(SELECT id FROM lock_type where name=_key)) ON CONFLICT DO NOTHING ;

                ELSE
                    DELETE FROM domain_lock WHERE domain_id=NEW.domain_id AND
                        type_id=tc_id_from_name('lock_type',_key);
                end if;
            end loop;
    end if;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
