INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key,
    is_noop
)
VALUES
    (
        'provision_contact_delete_group',
        'Groups delete for contact in backends',
        'provision_contact_delete',
        'provision_status',
        'status_id',
        NULL,
        TRUE
    ),
    (
        'provision_contact_delete',
        'delete contact in specific backend',
        'provision_contact_delete',
        'provision_status',
        'status_id',
        'WorkerJobContactProvision',
        FALSE
    )ON CONFLICT DO NOTHING;


DROP FUNCTION IF EXISTS delete_contact;
CREATE OR REPLACE FUNCTION delete_contact(delete_contact_id uuid) RETURNS VOID AS $$
BEGIN
    DELETE FROM ONLY contact_attribute where contact_id=delete_contact_id;
    DELETE FROM ONLY contact_postal where contact_id=delete_contact_id;
    DELETE FROM ONLY contact where id=delete_contact_id;
END;
$$ LANGUAGE plpgsql;



--------------------------------------------order changes------------------------------------------------------------




--
-- table: order_item_delete_contact
-- description: this table stores attributes of contact related orders.
--

CREATE TABLE IF NOT EXISTS order_item_delete_contact (
   contact_id                  UUID NOT NULL REFERENCES contact,
   PRIMARY KEY (id),
   FOREIGN KEY (order_id) REFERENCES "order",
   FOREIGN KEY (status_id) REFERENCES order_item_status
) INHERITS (order_item,class.audit_trail);

DROP VIEW IF EXISTS v_order_delete_contact;
CREATE OR REPLACE VIEW v_order_delete_contact AS
SELECT
    dc.id AS order_item_id,
    dc.order_id AS order_id,
    dc.contact_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name

FROM order_item_delete_contact dc
         JOIN "order" o ON o.id=dc.order_id
         JOIN v_order_type ot ON ot.id = o.type_id
         JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
         JOIN order_status s ON s.id = o.status_id
;



--
-- function: order_prevent_contact_domain_associated()
-- description: check if contact is associated with any domain
--
DROP TRIGGER IF EXISTS a_order_prevent_contact_in_use_tg ON order_item_delete_contact;
DROP TRIGGER IF EXISTS order_item_force_initial_status_tg ON order_item_delete_contact;
DROP TRIGGER IF EXISTS a_order_item_create_plan_tg ON order_item_delete_contact;
DROP TRIGGER IF EXISTS b_order_item_plan_start_tg ON order_item_delete_contact;
DROP TRIGGER IF EXISTS order_item_finish_tg ON order_item_delete_contact;

DROP FUNCTION IF EXISTS order_prevent_contact_in_use CASCADE;
CREATE OR REPLACE FUNCTION order_prevent_contact_in_use() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE FROM ONLY domain_contact WHERE contact_id=NEW.contact_id;

    IF FOUND THEN
        RAISE EXCEPTION 'cannot delete contact: in use.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE TRIGGER a_order_prevent_contact_in_use_tg
    BEFORE INSERT ON order_item_delete_contact
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_contact_in_use();

-- make sure the initial status is 'pending'
CREATE OR REPLACE TRIGGER order_item_force_initial_status_tg
    BEFORE INSERT ON order_item_delete_contact
    FOR EACH ROW EXECUTE PROCEDURE order_item_force_initial_status();

-- creates an execution plan for the item
CREATE OR REPLACE TRIGGER a_order_item_create_plan_tg
    AFTER UPDATE ON order_item_delete_contact
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    )EXECUTE PROCEDURE plan_simple_order_item();

-- starts the execution of the order
CREATE OR REPLACE TRIGGER b_order_item_plan_start_tg
    AFTER UPDATE ON order_item_delete_contact
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_status','ready')
    ) EXECUTE PROCEDURE order_item_plan_start();

-- when the order_item completes
CREATE OR REPLACE TRIGGER  order_item_finish_tg
    AFTER UPDATE ON order_item_delete_contact
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    ) EXECUTE PROCEDURE order_item_finish();

CREATE INDEX IF NOT EXISTS a_order_id ON order_item_delete_contact(order_id) ;
CREATE INDEX IF NOT EXISTS a_status_id ON order_item_delete_contact(status_id);

-- this table contains the plan for deleting a contact
CREATE TABLE IF NOT EXISTS delete_contact_plan(
    PRIMARY KEY(id),
    FOREIGN KEY (order_item_id) REFERENCES order_item_delete_contact
) INHERITS(order_item_plan,class.audit_trail);

DROP TRIGGER IF EXISTS plan_delete_contact_provision_contact_tg ON delete_contact_plan;
DROP TRIGGER IF EXISTS order_item_plan_update_tg ON delete_contact_plan;

DROP FUNCTION IF EXISTS plan_delete_contact_provision;
CREATE OR REPLACE FUNCTION plan_delete_contact_provision() RETURNS TRIGGER AS $$
DECLARE
    v_pcd_id            UUID;
    v_delete_contact    RECORD;
    _contact            RECORD;
BEGIN
    SELECT * INTO v_delete_contact FROM v_order_delete_contact v WHERE v.order_item_id = NEW.order_item_id;
    WITH pcd_ins AS (
        INSERT INTO provision_contact_delete (
                                              parent_id,
                                              accreditation_id,
                                              tenant_customer_id,
                                              order_metadata,
                                              contact_id,
                                              order_item_plan_ids
            ) VALUES (
                         NULL,
                         NULL,
                         v_delete_contact.tenant_customer_id,
                         v_delete_contact.order_metadata,
                         v_delete_contact.contact_id,
                         ARRAY [NEW.id]
                     ) RETURNING id
    )
    SELECT id INTO v_pcd_id FROM pcd_ins;

    FOR _contact IN SELECT * FROM ONLY provision_contact WHERE contact_id=v_delete_contact.contact_id
        LOOP
            INSERT INTO provision_contact_delete(
                parent_id,
                tenant_customer_id,
                contact_id,
                accreditation_id,
                handle
            ) VALUES (
                         v_pcd_id,
                         v_delete_contact.tenant_customer_id,
                         v_delete_contact.contact_id,
                         _contact.accreditation_id,
                         _contact.handle
                     ) ON CONFLICT DO NOTHING;
        END LOOP;
    IF NOT FOUND THEN
        PERFORM delete_contact(v_delete_contact.contact_id);
        UPDATE delete_contact_plan
        SET status_id = tc_id_from_name('order_item_plan_status','completed')
        WHERE id = NEW.id;

        RETURN NEW;
    end if;

    UPDATE provision_contact_delete SET is_complete = TRUE WHERE id = v_pcd_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER plan_delete_contact_provision_contact_tg
    AFTER UPDATE ON delete_contact_plan
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
        AND NEW.order_item_object_id = tc_id_from_name('order_item_object','contact')
    )
EXECUTE PROCEDURE plan_delete_contact_provision();

CREATE OR REPLACE TRIGGER order_item_plan_update_tg
    AFTER UPDATE ON delete_contact_plan
    FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
        AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
    )
EXECUTE PROCEDURE order_item_plan_update();






INSERT INTO order_item_strategy(order_type_id,object_id,provision_order) values
     (
         (SELECT type_id FROM v_order_product_type WHERE product_name='contact' AND type_name='delete'),
         tc_id_from_name('order_item_object','contact'),
         1
     );

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
;



--------------------------------------------provision changes-----------------------------------------------------------
DROP TRIGGER IF EXISTS provision_contact_delete_job_tg ON provision_contact_delete;
DROP TRIGGER IF EXISTS provision_contact_delete_success_tg ON provision_contact_delete;

DROP FUNCTION IF EXISTS provision_contact_delete_job;
CREATE OR REPLACE FUNCTION provision_contact_delete_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id      UUID;
    _child_jobs         RECORD;
    v_contact           RECORD;
BEGIN

    SELECT job_create(
                   NEW.tenant_customer_id,
                   'provision_contact_delete_group',
                   NEW.id,
                   to_jsonb(NULL::jsonb)
           ) INTO _parent_job_id;

    UPDATE provision_contact_delete SET job_id= _parent_job_id WHERE id = NEW.id;


    FOR _child_jobs IN
        SELECT *
        FROM provision_contact_delete pcd
        WHERE pcd.parent_id = NEW.id
        LOOP
            SELECT
                TO_JSONB(a.*) AS accreditation,
                _child_jobs.handle AS handle,
                _child_jobs.order_metadata AS order_metadata
            INTO v_contact
            FROM v_accreditation a
            WHERE a.accreditation_id = _child_jobs.accreditation_id;

            UPDATE provision_contact_delete SET job_id=job_submit(
                    _child_jobs.tenant_customer_id,
                    'provision_contact_delete',
                    _child_jobs.id,
                    to_jsonb(v_contact.*),
                    _parent_job_id,
                    FALSE
                                                       ) WHERE id = _child_jobs.id;
        END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS provision_contact_delete_success;
CREATE OR REPLACE FUNCTION provision_contact_delete_success() RETURNS TRIGGER AS $$
BEGIN
    PERFORM delete_contact(NEW.contact_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TABLE IF NOT EXISTS provision_contact_delete (
  parent_id                       UUID REFERENCES provision_contact_delete ON DELETE CASCADE,
  contact_id                      UUID NOT NULL REFERENCES contact,
  accreditation_id                UUID REFERENCES accreditation,
  handle                          TEXT,
  is_complete                     BOOLEAN NOT NULL DEFAULT FALSE,
  order_metadata                  JSONB,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

CREATE INDEX IF NOT EXISTS idx_parent_id ON provision_contact_delete (parent_id);

CREATE OR REPLACE TRIGGER provision_contact_delete_job_tg
    AFTER UPDATE ON provision_contact_delete
    FOR EACH ROW WHEN (OLD.is_complete <> NEW.is_complete AND NEW.is_complete)
EXECUTE PROCEDURE provision_contact_delete_job();

CREATE OR REPLACE TRIGGER provision_contact_delete_success_tg
    AFTER UPDATE ON provision_contact_delete
    FOR EACH ROW WHEN (
    NEW.is_complete
        AND OLD.status_id <> NEW.status_id AND NEW.parent_id IS NULL
        AND NEW.status_id = tc_id_from_name('provision_status','completed')
    ) EXECUTE PROCEDURE provision_contact_delete_success();

\i triggers.ddl
\i provisioning/triggers.ddl