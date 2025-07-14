-- add not before not after to certificate
ALTER TABLE hosting_certificate
ADD COLUMN IF NOT EXISTS not_before TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS not_after  TIMESTAMPTZ;

INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key
) VALUES (
    'provision_hosting_certificate_create',
    'Provisions a new hosting certificate',
    'provision_hosting_certificate_create',
    'provision_status',
    'status_id',
    'WorkerJobHostingCertificateProvision'
) ON CONFLICT DO NOTHING; 

INSERT INTO job_type(
    name,
    descr,
    reference_status_table,
    reference_status_column,
    routing_key
) VALUES (
    'provision_hosting_dns_check',
    'Check if a user has configured DNS for a hosting request',
    'provision_status',
    'status_id',
    'WorkerJobHostingDNSCheck'
) ON CONFLICT DO NOTHING;

DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.TABLES
            WHERE table_schema = 'public'
            AND TABLE_NAME = 'order_item_create_hosting_certificate') THEN
        ALTER TABLE order_item_create_hosting_certificate RENAME TO order_hosting_certificate;
    END IF;
END$$;

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
    );

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

DROP TRIGGER IF EXISTS order_item_create_hosting_record_tg ON order_item_create_hosting;

CREATE TRIGGER order_item_create_hosting_record_tg
    AFTER INSERT ON order_item_create_hosting
    FOR EACH ROW EXECUTE PROCEDURE order_item_create_hosting_record();   

CREATE OR REPLACE FUNCTION plan_create_hosting_certificate_provision() RETURNS TRIGGER AS $$
DECLARE
    v_create_hosting RECORD;
    v_create_hosting_certificate RECORD;
BEGIN

    SELECT * INTO v_create_hosting
    FROM v_order_create_hosting
    WHERE order_item_id = NEW.order_item_id;

    IF v_create_hosting.certificate_id IS NOT NULL THEN
        UPDATE create_hosting_plan
        SET status_id = tc_id_from_name('order_item_plan_status', 'completed')
        WHERE id = NEW.id;
    ELSE
        INSERT INTO provision_hosting_certificate_create (
            domain_name,
            hosting_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES (
                    v_create_hosting.domain_name,
                    v_create_hosting.hosting_id,
                    v_create_hosting.tenant_customer_id,
                    v_create_hosting.order_metadata,
                    ARRAY[NEW.id]
                );


    END IF;


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS plan_create_hosting_certificate_provision_tg ON create_hosting_plan;
CREATE TRIGGER plan_create_hosting_certificate_provision_tg
    AFTER UPDATE ON create_hosting_plan
    FOR EACH ROW WHEN (
            OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status', 'processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','hosting_certificate')
    )
EXECUTE  PROCEDURE plan_create_hosting_certificate_provision();

INSERT INTO order_item_object(name,descr)
VALUES ('hosting_certificate', 'hosting certificate object')
ON CONFLICT DO NOTHING;

DELETE FROM order_item_strategy WHERE order_type_id = (SELECT type_id FROM v_order_product_type WHERE product_name='hosting' AND type_name='create');

INSERT INTO order_item_strategy(order_type_id,object_id,provision_order)
  VALUES
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='hosting' AND type_name='create'),
        tc_id_from_name('order_item_object','hosting_certificate'),
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='hosting' AND type_name='create'),
        tc_id_from_name('order_item_object','hosting'),
        2
    ) ON CONFLICT DO NOTHING;


CREATE OR REPLACE VIEW v_order_item_plan_object AS 
SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_contact.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM create_domain_contact
    WHERE create_domain_id = d.id
  ) AS distinct_order_contact ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_host.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
  JOIN LATERAL (
    SELECT DISTINCT id AS id
    FROM create_domain_nameserver
    WHERE create_domain_id = d.id
  ) AS distinct_order_host ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_create_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_renew_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id AS object_id,
  d.id AS id
FROM order_item_redeem_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj on obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_delete_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  distinct_order_contact.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'
  JOIN LATERAL (
    SELECT DISTINCT order_contact_id AS id
    FROM update_domain_contact
    WHERE update_domain_id = d.id
  ) AS distinct_order_contact ON TRUE

UNION

SELECT
  d.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  d.id AS id
FROM order_item_update_domain d
  JOIN "order" o ON o.id = d.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'domain'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_create_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting_certificate'

UNION


SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_delete_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_update_hosting c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'hosting'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_create_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_update_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  c.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  c.id AS id
FROM order_item_delete_contact c
  JOIN "order" o ON o.id = c.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'contact'

UNION

SELECT
  h.id AS order_item_id,
  p.name AS product_name,
  ot.name AS order_type_name,
  obj.name AS object_name,
  obj.id   AS object_id,
  h.id AS id
FROM order_item_update_host h
  JOIN "order" o ON o.id = h.order_id
  JOIN order_type ot ON ot.id = o.type_id
  JOIN product p ON p.id = ot.product_id
  JOIN order_item_object obj ON obj.name = 'host'
;

DROP VIEW IF EXISTS v_order_create_hosting;
CREATE OR REPLACE VIEW v_order_create_hosting AS
SELECT
    ch.id AS hosting_id,
    ch.id AS order_item_id,
    ch.order_id AS order_id,
    ch.domain_name,
    ch.region_id,
    ch.product_id,
    chc.id AS client_id,
    chcr.id AS certificate_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.tenant_name,
    tc.name
FROM order_item_create_hosting ch
    JOIN order_item_create_hosting_client chc ON chc.id = ch.client_id
    LEFT OUTER JOIN order_hosting_certificate chcr ON ch.certificate_id = chcr.id
    JOIN "order" o ON o.id=ch.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id;

CREATE TABLE IF NOT EXISTS provision_hosting_certificate_create (
    hosting_id              UUID NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (hosting_id) REFERENCES order_item_create_hosting,
    domain_name             TEXT NOT NULL,
    body                    TEXT,
    chain                   TEXT,
    private_key             TEXT,
    not_before              TIMESTAMPTZ,
    not_after               TIMESTAMPTZ
) INHERITS (class.audit_trail, class.provision);

CREATE OR REPLACE FUNCTION provision_hosting_certificate_create_job() RETURNS TRIGGER AS $$
DECLARE
    v_cert_data record;
    v_dns_check_data record;
    _parent_job_id uuid;
    _child_job_id uuid;
BEGIN

    SELECT
        NEW.id as provision_hosting_create_id,
        phc.hosting_id as request_id,
        phc.tenant_customer_id,
        phc.domain_name,
        phc.order_metadata
    INTO v_cert_data
    FROM provision_hosting_certificate_create phc
    WHERE phc.id = NEW.id;

    SELECT 
        phc.domain_name,
        phc.order_metadata
    INTO v_dns_check_data
    FROM provision_hosting_certificate_create phc
    WHERE phc.id = NEW.id;

    -- create a certificate job but don't submit it
    SELECT job_create(
        v_cert_data.tenant_customer_id,
        'provision_hosting_certificate_create',
        NEW.id,
        to_jsonb(v_cert_data)
    ) INTO _parent_job_id;

    UPDATE provision_hosting_certificate_create SET job_id = _parent_job_id WHERE id = NEW.id;

    SELECT job_submit_retriable(
        v_cert_data.tenant_customer_id,
        'provision_hosting_dns_check',
        -- doesn't matter what we set for reference id, this job type will not have a reference table
        NEW.id,
        to_jsonb(v_dns_check_data),
        NOW(),
        INTERVAL '4 hours',
        18,
        _parent_job_id
    ) INTO _child_job_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION provision_hosting_certificate_create_update_hosting_status() RETURNS TRIGGER AS $$
    BEGIN
        UPDATE ONLY hosting
        SET status = 'Pending Certificate Setup'
        WHERE id = NEW.hosting_id;
        RETURN NEW;
    END;
$$ LANGUAGE plpgsql;


-- function: provision_hosting_certificate_create_success
-- description: updates the hosting certificate
CREATE OR REPLACE FUNCTION provision_hosting_certificate_create_success() RETURNS TRIGGER AS $$
DECLARE
        v_certificate_id UUID;
BEGIN
    INSERT INTO hosting_certificate
    (body, chain, private_key, not_before, not_after)
    SELECT body, chain, private_key, not_before, not_after
    FROM provision_hosting_certificate_create
    WHERE id = NEW.id RETURNING id INTO v_certificate_id; 

    -- update hosting record
    UPDATE ONLY hosting
    SET certificate_id = v_certificate_id
    WHERE id = NEW.hosting_id;


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS provision_hosting_certificate_create_job_tg ON provision_hosting_certificate_create;
DROP TRIGGER IF EXISTS provision_hosting_certificate_create_success_tg ON provision_hosting_certificate_create;
DROP TRIGGER IF EXISTS provision_hosting_certificate_create_update_hosting_status_tg ON provision_hosting_certificate_create;

CREATE TRIGGER provision_hosting_certificate_create_job_tg
    AFTER INSERT ON provision_hosting_certificate_create
    FOR EACH ROW EXECUTE PROCEDURE provision_hosting_certificate_create_job();

-- Trigger when the operation is successful
CREATE TRIGGER provision_hosting_certificate_create_success_tg
    AFTER UPDATE ON provision_hosting_certificate_create
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id AND
        NEW.status_id = tc_id_from_name('provision_status', 'completed')
    ) EXECUTE PROCEDURE provision_hosting_certificate_create_success();

-- Trigger to keep hosting status up to date
CREATE TRIGGER provision_hosting_certificate_create_update_hosting_status_tg
    AFTER UPDATE ON provision_hosting_certificate_create
    FOR EACH ROW WHEN (
        OLD.status_id <> NEW.status_id AND
        NEW.status_id = tc_id_from_name('provision_status', 'pending_action')
    ) EXECUTE PROCEDURE provision_hosting_certificate_create_update_hosting_status();

CREATE OR REPLACE FUNCTION provision_hosting_create_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
        v_cuser RECORD;
        v_certificate RECORD;
    BEGIN

        IF NEW.certificate_id IS NULL THEN
            SELECT body, private_key, chain INTO v_certificate FROM provision_hosting_certificate_create phc WHERE phc.hosting_id = NEW.hosting_id;
        ELSE
            SELECT body, private_key, chain INTO v_certificate FROM hosting_certificate WHERE id = NEW.certificate_id;
        END IF;


        -- find single customer user (temporary)
        SELECT *
        INTO v_cuser
        FROM v_customer_user vcu
        JOIN v_tenant_customer vtnc ON vcu.customer_id = vtnc.customer_id
        WHERE vtnc.id = NEW.tenant_customer_id 
        LIMIT 1;

        WITH components AS (
          SELECT  JSON_AGG(
                    JSONB_BUILD_OBJECT(
                      'name', hc.name,
                      'type', tc_name_from_id('hosting_component_type', hc.type_id)
                    )
                  ) AS data   
          FROM hosting_component hc
          JOIN hosting_product_component hpc ON hpc.component_id = hc.id
          JOIN provision_hosting_create ph ON ph.product_id = hpc.product_id 
          WHERE ph.id = NEW.id
        )
        SELECT
          NEW.id as provision_hosting_create_id,
          vtnc.id AS tenant_customer_id,
          ph.domain_name,
          ph.product_id,
          ph.region_id,
          ph.order_metadata AS metadata,
          vtnc.name as customer_name,
          v_cuser.email as customer_email,
          TO_JSONB(hc.*) AS client,
          TO_JSONB(v_certificate.*) AS certificate,
          components.data AS components
        INTO v_hosting
        FROM provision_hosting_create ph
        JOIN components ON TRUE
        JOIN hosting_client hc ON hc.id = ph.client_id
        JOIN v_tenant_customer vtnc ON vtnc.id = ph.tenant_customer_id
        WHERE ph.id = NEW.id;

        UPDATE provision_hosting_create SET job_id = job_submit(
            v_hosting.tenant_customer_id,
            'provision_hosting_create',
            NEW.id,
            to_jsonb(v_hosting.*)
            ) WHERE id = NEW.id;


        RETURN NEW;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION provision_hosting_create_success() RETURNS TRIGGER AS $$
BEGIN


    WITH hosting_update AS (
        UPDATE ONLY hosting
            SET
            -- do we need this? it looks like the worker is going
            -- to update the hosting object
                status = NEW.status,
                is_active = NEW.is_active,
                is_deleted = NEW.is_deleted,
                external_order_id = NEW.external_order_id
            WHERE id = NEW.hosting_id
            RETURNING client_id
    )
    UPDATE ONLY hosting_client
        SET
            external_client_id = NEW.external_client_id,
            username = NEW.client_username
        WHERE id = (SELECT client_id FROM hosting_update) AND external_client_id IS NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;