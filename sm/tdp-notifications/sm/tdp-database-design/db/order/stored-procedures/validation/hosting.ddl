-- function: order_item_check_hosting_deleted
-- description: prevents hosting update/delete if hosting deleted
CREATE OR REPLACE FUNCTION order_item_check_hosting_deleted() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM ONLY hosting WHERE id=NEW.hosting_id AND NOT is_deleted;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hosting ''%'' not found', NEW.hosting_id USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_item_create_hosting_record()
-- description: creates the hosting object which we will manipulate during order processing
CREATE OR REPLACE FUNCTION order_item_create_hosting_record() RETURNS TRIGGER AS $$
DECLARE
    v_hosting_client RECORD;
BEGIN

    SELECT * INTO v_hosting_client
    FROM hosting_client
    WHERE id = NEW.client_id;

    INSERT INTO hosting_client (
        id,
        tenant_customer_id,
        external_client_id,
        name,
        email,
        username,
        password,
        is_active
    ) VALUES (
                 v_hosting_client.id,
                 v_hosting_client.tenant_customer_id,
                 v_hosting_client.external_client_id,
                 v_hosting_client.name,
                 v_hosting_client.email,
                 v_hosting_client.username,
                 v_hosting_client.password,
                 v_hosting_client.is_active
             ) ON CONFLICT DO NOTHING;

    IF NEW.certificate_id IS NOT NULL THEN
        INSERT INTO hosting_certificate (
            SELECT * FROM hosting_certificate WHERE id=NEW.certificate_id
        );
    END IF;

    -- insert all the values from new into hosting
    INSERT INTO hosting (
        id,
        domain_name,
        product_id,
        region_id,
        client_id,
        tenant_customer_id,
        certificate_id,
        external_order_id,
        hosting_status_id,
        descr,
        is_active,
        is_deleted,
        tags,
        metadata
    )
    VALUES (
               NEW.id,
               NEW.domain_name,
               NEW.product_id,
               NEW.region_id,
               NEW.client_id,
               NEW.tenant_customer_id,
               NEW.certificate_id,
               NEW.external_order_id,
               NEW.hosting_status_id,
               NEW.descr,
               NEW.is_active,
               NEW.is_deleted,
               NEW.tags,
               NEW.metadata
           );

    RETURN NEW;
END $$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION enforce_single_active_hosting_order_by_name() RETURNS TRIGGER AS $$
BEGIN
    -- code

    -- query v_hosting_order_item where hosting name is the same and not status is final
    -- if any results are found, raise an exception

    PERFORM 1 FROM v_hosting_order_item WHERE domain_name = NEW.domain_name AND NOT order_status_is_final LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Active order for Hosting ''%'' currently exists', NEW.domain_name USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;

END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_single_active_hosting_order_by_id() RETURNS TRIGGER AS $$
DECLARE
    hosting_name TEXT;
BEGIN
    -- code

    -- query v_hosting_order_item where hosting name is the same and not status is final
    -- if any results are found, raise an exception

    SELECT domain_name FROM hosting WHERE id = NEW.hosting_id INTO hosting_name;

    PERFORM 1 FROM v_hosting_order_item WHERE domain_name = hosting_name AND NOT order_status_is_final LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Active order for Hosting ''%'' currently exists', hosting_name USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END $$ LANGUAGE plpgsql;