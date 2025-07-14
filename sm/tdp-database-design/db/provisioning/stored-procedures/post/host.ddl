-- function: provision_host_success()
-- description: set the host parent domain for provisioned host
CREATE OR REPLACE FUNCTION provision_host_success() RETURNS TRIGGER AS $$
DECLARE
BEGIN
    -- create new host if does not exist already
    INSERT INTO host (
        id,
        name,
        domain_id,
        tenant_customer_id,
        tags,
        metadata
    ) VALUES (
        NEW.host_id,
        NEW.name,
        NEW.domain_id,
        NEW.tenant_customer_id,
        NEW.tags,
        NEW.metadata
    ) ON CONFLICT (id)
    DO UPDATE
    -- set parent domain id if was null before
    SET domain_id = COALESCE(host.domain_id, EXCLUDED.domain_id);

    -- add new addresses
    INSERT INTO host_addr (host_id, address)
    SELECT NEW.host_id, unnest(NEW.addresses)
    ON CONFLICT (host_id, address) DO NOTHING;

    -- remove old addrs in case host was created on update
    DELETE FROM host_addr
    WHERE host_id = NEW.host_id AND (address != ALL(NEW.addresses));

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_host_update_success()
-- description: updates the host once the provision job completes
CREATE OR REPLACE FUNCTION provision_host_update_success() RETURNS TRIGGER AS $$
DECLARE
    new_host_addrs INET[];
BEGIN

    -- add new addrs
    INSERT INTO host_addr (host_id, address)
    SELECT NEW.host_id, unnest(NEW.addresses)
    ON CONFLICT (host_id, address) DO NOTHING;

    -- remove old addrs
    DELETE FROM host_addr
    WHERE host_id = NEW.host_id AND (address != ALL(NEW.addresses));

    -- set host parent domain if needed
    UPDATE ONLY host h
    SET domain_id = NEW.domain_id
    WHERE h.id = NEW.host_id AND h.domain_id IS NULL;

    UPDATE ONLY host h
    SET updated_date = NEW.updated_date
    WHERE NEW.updated_date IS NOT NULL AND h.id = NEW.host_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_host_delete_success()
-- description: deletes the host once the provision job completes
CREATE OR REPLACE FUNCTION provision_host_delete_success() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM ONLY host where id=NEW.host_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
