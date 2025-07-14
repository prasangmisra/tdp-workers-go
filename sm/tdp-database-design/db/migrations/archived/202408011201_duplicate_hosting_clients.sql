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
        status,
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
               NEW.status,
               NEW.descr,
               NEW.is_active,
               NEW.is_deleted,
               NEW.tags,
               NEW.metadata
           );

    RETURN NEW;
END $$ LANGUAGE plpgsql;