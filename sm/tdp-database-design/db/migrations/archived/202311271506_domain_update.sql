-- add unique_attr_key_unique_name_and_category_id constraint 
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'unique_attr_key_unique_name_and_category_id' 
            AND table_name = 'attr_key'
    ) THEN
        ALTER TABLE attr_key
        ADD CONSTRAINT unique_attr_key_unique_name_and_category_id
        UNIQUE (name,category_id);
    END IF;
END $$;

-- INSERT
INSERT INTO
    job_type(
         name,
         descr,
         reference_table,
         reference_status_table,
         reference_status_column,
         routing_key
)
VALUES(
       'provision_domain_update',
       'Updates a domain in the backend',
       'provision_domain_update',
       'provision_status',
       'status_id',
       'WorkerJobDomainProvision'
) ON CONFLICT DO NOTHING;

WITH strat AS (
    SELECT
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update') AS order_type_id,
        tc_id_from_name('order_item_object','contact') AS object_id,
        1 AS provision_order
)
INSERT INTO order_item_strategy(order_type_id,object_id,provision_order)
SELECT * FROM strat
WHERE NOT EXISTS (
    SELECT 1
    FROM order_item_strategy
    WHERE
        order_type_id = strat.order_type_id
        AND object_id = strat.object_id
        AND provision_order = strat.provision_order
);

WITH strat AS (
    SELECT
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update') AS order_type_id,
        tc_id_from_name('order_item_object','domain') AS object_id,
        2 AS provision_order
)
INSERT INTO order_item_strategy(order_type_id,object_id,provision_order)
SELECT * FROM strat
WHERE NOT EXISTS (
    SELECT 1
    FROM order_item_strategy
    WHERE
        order_type_id = strat.order_type_id
        AND object_id = strat.object_id
        AND provision_order = strat.provision_order
);

INSERT INTO attr_key(
    name,
    category_id,
    descr,
    value_type_id,
    default_value,
    allow_null)
VALUES(
    'max_nameservers',
    (SELECT id FROM attr_category WHERE name='dns'),
    'Minimum required nameservers by registry',
    (SELECT id FROM attr_value_type WHERE name='INTEGER'),
    13::TEXT,
    FALSE
),
(
  'required_contact_types',
  (SELECT id FROM attr_category WHERE name='contact'),
  'Required contact types by registry',
  (SELECT id FROM attr_value_type WHERE name='TEXT_LIST'),
  ARRAY['registrant']::TEXT,
  TRUE
) ON CONFLICT DO NOTHING;

UPDATE attr_key SET descr = 'Minimum required nameservers by registry' 
WHERE name = 'min_nameservers';

-- CREATE
CREATE TABLE IF NOT EXISTS order_item_update_domain (
    name                  FQDN NOT NULL,
    auth_info             TEXT,
    hosts                 TEXT[],
    accreditation_tld_id  UUID NOT NULL REFERENCES accreditation_tld,
    PRIMARY KEY (id),
    FOREIGN KEY (order_id) REFERENCES "order",
    FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

CREATE OR REPLACE TRIGGER order_item_force_initial_status_tg
BEFORE INSERT ON order_item_update_domain
FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- sets the TLD_ID on when the it does not contain one
CREATE OR REPLACE TRIGGER order_item_set_tld_id_tg
BEFORE INSERT ON order_item_update_domain
FOR EACH ROW WHEN ( NEW.accreditation_tld_id IS NULL)
EXECUTE PROCEDURE order_item_set_tld_id();

CREATE OR REPLACE FUNCTION order_prevent_if_domain_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    v_domain    RECORD;
BEGIN
    SELECT * INTO v_domain
    FROM domain d
    JOIN "order" o ON o.id=NEW.order_id  
    WHERE d.name=NEW.name
      AND d.tenant_customer_id=o.tenant_customer_id
      AND d.status_id = tc_id_from_name('domain_status', 'active');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Domain ''%'' not found', NEW.name USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION order_prevent_if_nameserver_does_not_exist() RETURNS TRIGGER AS $$
DECLARE
    _hosts_exist  BOOL;
BEGIN

    -- @> operator checks of the first array contains the seconds.
    -- @> can return null if there's no value so we use COALESCE
    SELECT COALESCE(ARRAY_AGG(h.name), ARRAY[]::TEXT[]) @> NEW.hosts
    INTO _hosts_exist
    FROM host h
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = NEW.accreditation_tld_id
    JOIN provision_host ph ON 
        ph.host_id = h.id
        AND ph.accreditation_id = vat.accreditation_id
    WHERE h.name = ANY(NEW.hosts);

    IF NOT _hosts_exist THEN
        RAISE EXCEPTION 'One or more nameservers do not exist: ''%''', NEW.hosts USING ERRCODE = 'no_data_found';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION order_prevent_if_nameservers_count_is_invalid() RETURNS TRIGGER AS $$
DECLARE
    v_order         RECORD;
    v_domain        RECORD;
    _min_ns_attr    INT;
    _max_ns_attr    INT;
    _hosts_count    INT;
BEGIN

    SELECT * INTO v_order
    FROM "order"
    WHERE id=NEW.order_id;

    SELECT * INTO v_domain
    FROM domain
    WHERE name=NEW.name
      AND tenant_customer_id=v_order.tenant_customer_id
      AND status_id = tc_id_from_name('domain_status', 'active');

    SELECT va.value::INT INTO _min_ns_attr
    FROM v_attribute va
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_domain.accreditation_tld_id
    WHERE va.key = 'tld.dns.min_nameservers'
      AND va.tld_name = vat.tld_name;

    SELECT va.value::INT INTO _max_ns_attr
    FROM v_attribute va
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = v_domain.accreditation_tld_id
    WHERE va.key = 'tld.dns.max_nameservers'
      AND va.tld_name = vat.tld_name;

    SELECT CARDINALITY(NEW.hosts) INTO _hosts_count;

    IF _hosts_count < _min_ns_attr OR _hosts_count > _max_ns_attr THEN
        RAISE EXCEPTION 'Nameserver count must be in this range %-%', _min_ns_attr,_max_ns_attr;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- prevents order creation for already non-existing domain
CREATE OR REPLACE TRIGGER order_prevent_if_domain_does_not_exist_tg
BEFORE INSERT ON order_item_update_domain
FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();

-- prevents order creation for non-existing nameservers
CREATE OR REPLACE TRIGGER order_prevent_if_nameserver_does_not_exist_tg
BEFORE INSERT ON order_item_update_domain
FOR EACH ROW WHEN (NEW.hosts IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_nameserver_does_not_exist();

-- prevents order creation if ns count is invalid
CREATE OR REPLACE TRIGGER order_prevent_if_nameservers_count_is_invalid_tg
BEFORE INSERT ON order_item_update_domain
FOR EACH ROW WHEN (NEW.hosts IS NOT NULL)
EXECUTE PROCEDURE order_prevent_if_nameservers_count_is_invalid();

-- updates an execution plan for the item
CREATE OR REPLACE TRIGGER a_order_item_update_plan_tg
AFTER UPDATE ON order_item_update_domain
FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
)
EXECUTE PROCEDURE plan_order_item();

-- starts the execution of the order
CREATE OR REPLACE TRIGGER b_order_item_plan_start_tg
AFTER UPDATE ON order_item_update_domain
FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_status','ready')
)
EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE OR REPLACE TRIGGER  order_item_finish_tg
AFTER UPDATE ON order_item_update_domain
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
)
EXECUTE PROCEDURE order_item_finish();

CREATE INDEX ON order_item_update_domain(order_id);
CREATE INDEX ON order_item_update_domain(status_id);


CREATE TABLE IF NOT EXISTS update_domain_contact(
    id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
    domain_contact_type_id  UUID NOT NULL REFERENCES domain_contact_type,
    order_contact_id        UUID REFERENCES order_contact,
    UNIQUE(update_domain_id,domain_contact_type_id,order_contact_id)
) INHERITS(class.audit);

CREATE INDEX ON update_domain_contact(update_domain_id);
CREATE INDEX ON update_domain_contact(domain_contact_type_id);
CREATE INDEX ON update_domain_contact(order_contact_id);

COMMENT ON TABLE update_domain_contact IS
'contains the association of contacts and domains at order time';

COMMENT ON COLUMN update_domain_contact.order_contact_id IS
'since the order_contact table inherits from the contact table, the
data will be available in the contact, this also allow for contact
reutilization';

-- this table contains the plan for creating a domain
CREATE TABLE IF NOT EXISTS update_domain_plan(
    PRIMARY KEY(id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_update_domain
) INHERITS(order_item_plan,class.audit_trail);

CREATE OR REPLACE FUNCTION plan_update_domain_provision_contact() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain       RECORD;
    _order_contact        RECORD;
BEGIN

    SELECT *
    INTO _order_contact
    FROM order_contact
    WHERE id=NEW.reference_id;

    IF NOT FOUND THEN
       RAISE EXCEPTION 'reference id % not found in order_contact table',NEW.reference_id;
    END IF;

    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    INSERT INTO contact (SELECT * FROM contact WHERE id=NEW.reference_id);
    INSERT INTO contact_postal (SELECT * FROM contact_postal WHERE contact_id=NEW.reference_id);

    INSERT INTO provision_contact(
        contact_id,
        accreditation_id,
        tenant_customer_id,
        order_item_plan_ids
    ) VALUES(
        NEW.reference_id,
        v_update_domain.accreditation_id,
        v_update_domain.tenant_customer_id,
        ARRAY[NEW.id]
    );

RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER plan_update_domain_provision_contact_tg
AFTER UPDATE ON update_domain_plan
FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','contact')
)
EXECUTE PROCEDURE plan_update_domain_provision_contact();

CREATE OR REPLACE FUNCTION plan_update_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_pd_id                     UUID;
BEGIN

    -- order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;

    -- we now signal the provisioning
    WITH pd_ins AS (
    INSERT INTO provision_domain_update(
        name,
        auth_info,
        hosts,
        accreditation_id,
        accreditation_tld_id,
        tenant_customer_id,
        order_item_plan_ids
    ) VALUES(
        v_update_domain.domain_name,
        v_update_domain.auth_info,
        v_update_domain.hosts,
        v_update_domain.accreditation_id,
        v_update_domain.accreditation_tld_id,
        v_update_domain.tenant_customer_id,
        ARRAY[NEW.id]
        ) RETURNING id
        )
    SELECT id INTO v_pd_id FROM pd_ins;

    -- insert contacts
    INSERT INTO provision_domain_update_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )
    (
        SELECT
            v_pd_id,
            order_contact_id,
            domain_contact_type_id
        FROM update_domain_contact
        WHERE update_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain_update SET is_complete = TRUE WHERE id = v_pd_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER plan_update_domain_provision_domain_tg
AFTER UPDATE ON update_domain_plan
FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
    AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
)
EXECUTE PROCEDURE plan_update_domain_provision_domain();

CREATE OR REPLACE TRIGGER order_item_plan_update_tg
AFTER UPDATE ON update_domain_plan
FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
)
EXECUTE PROCEDURE order_item_plan_update();

-- dropping view is needed when a column is remove from view
DROP VIEW IF EXISTS v_order_update_domain;

CREATE OR REPLACE VIEW v_order_update_domain AS
SELECT
    ud.id AS order_item_id,
    ud.order_id AS order_id,
    ud.accreditation_tld_id,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name,
    at.provider_name,
    at.provider_instance_id,
    at.provider_instance_name,
    at.tld_id AS tld_id,
    at.tld_name AS tld_name,
    at.accreditation_id,
    d.name AS domain_name,
    d.id AS domain_id,
    ud.auth_info,
    ud.hosts
FROM order_item_update_domain ud
    JOIN "order" o ON o.id=ud.order_id
    JOIN v_order_type ot ON ot.id = o.type_id
    JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
    JOIN order_status s ON s.id = o.status_id
    JOIN v_accreditation_tld at ON at.accreditation_tld_id = ud.accreditation_tld_id
    JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=ud.name
;

CREATE TABLE IF NOT EXISTS provision_domain_update (
    name                    FQDN NOT NULL,
    auth_info               TEXT,
    hosts                   TEXT[],
    accreditation_id        UUID NOT NULL REFERENCES accreditation,
    accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
    is_complete             BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id),
    FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer
) INHERITS (class.audit_trail,class.provision);


CREATE OR REPLACE FUNCTION provision_domain_update_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
BEGIN
    WITH contacts AS(
        SELECT JSONB_AGG(
                       JSONB_BUILD_OBJECT(
                               'type', ct.name,
                               'handle', pc.handle
                       )
               ) AS data
        FROM provision_domain_update_contact pdc
        JOIN domain_contact_type ct ON ct.id =  pdc.contact_type_id
        JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        JOIN provision_status ps ON ps.id = pc.status_id
        WHERE
            ps.is_success AND ps.is_final
            AND pdc.provision_domain_update_id = NEW.id
    ), hosts AS(
        SELECT JSONB_AGG(data) AS data
        FROM(
                SELECT
                    JSON_BUILD_OBJECT(
                            'name', h.name,
                            'ip_addresses', JSONB_AGG(ha.address)
                    ) AS data
                FROM host h
                JOIN host_addr ha ON h.id = ha.host_id
                WHERE h.name IN (SELECT UNNEST(NEW.hosts))
                GROUP BY h.name
            ) sub_q
    )
    SELECT
        NEW.id AS provision_domain_update_id,
        tnc.id AS tenant_customer_id,
        d.name AS name,
        d.auth_info AS pw,
        contacts.data AS contacts,
        hosts.data as nameservers,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld
    INTO v_domain
    FROM provision_domain_update d
    LEFT JOIN contacts ON TRUE
    LEFT JOIN hosts ON TRUE
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE d.id = NEW.id;

    UPDATE provision_domain_update SET
        job_id = job_create(
                v_domain.tenant_customer_id,
                'provision_domain_update',
                NEW.id,
                TO_JSONB(v_domain.*)
        ) WHERE id=NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER provision_domain_update_job_tg
AFTER UPDATE ON provision_domain_update
FOR EACH ROW WHEN (OLD.is_complete <> NEW.is_complete AND NEW.is_complete)
EXECUTE PROCEDURE provision_domain_update_job();

-- COMMENT ON TRIGGER provision_domain_update_job_tg IS 'creates a job when the provision data is complete';

CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
BEGIN

    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
        d.id,
        pdc.contact_id,
        pdc.contact_type_id,
        pc.handle
        FROM provision_domain_update_contact pdc
        JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        JOIN domain d ON d.name = NEW.name
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
        DO UPDATE SET contact_id = EXCLUDED.contact_id;

    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            d.id,
            h.id
        FROM domain d
                JOIN host h
                    ON h.name IN (SELECT UNNEST(NEW.hosts))
                        AND d.name = NEW.name
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;

    -- delete removed hosts
    DELETE FROM domain_host dh
    USING
        domain d,
        host h
    WHERE
        NEW.hosts IS NOT NULL
    AND d.name = NEW.name
    AND h.name NOT IN (SELECT UNNEST(NEW.hosts))
    AND dh.domain_id = d.id
    AND dh.host_id = h.id;

RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER provision_domain_update_success_tg
AFTER UPDATE ON provision_domain_update
FOR EACH ROW WHEN (
    NEW.is_complete
    AND OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
) EXECUTE PROCEDURE provision_domain_update_success();

-- COMMENT ON TRIGGER provision_domain_update_success_tg IS 'creates the domain after the provision_domain_update is done';

CREATE TABLE IF NOT EXISTS provision_domain_update_contact(
    id                                UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    provision_domain_update_id        UUID NOT NULL REFERENCES provision_domain_update ON DELETE CASCADE,
    contact_id                        UUID NOT NULL REFERENCES contact,
    contact_type_id                   UUID NOT NULL REFERENCES domain_contact_type,
    UNIQUE(provision_domain_update_id,contact_id,contact_type_id)
) INHERITS(class.audit);




-- ALTER
ALTER TABLE IF EXISTS domain_contact DROP CONSTRAINT IF EXISTS domain_contact_domain_id_contact_id_domain_contact_type_id_key;
ALTER TABLE IF EXISTS domain_contact DROP CONSTRAINT IF EXISTS domain_contact_domain_id_domain_contact_type_id_key;
ALTER TABLE IF EXISTS domain_contact ADD CONSTRAINT domain_contact_domain_id_domain_contact_type_id_key UNIQUE (domain_id, domain_contact_type_id);

DROP VIEW IF EXISTS v_order_item_plan_object;
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

;

\i triggers.ddl
\i provisioning/triggers.ddl

