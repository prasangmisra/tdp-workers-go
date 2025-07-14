--
-- table: transfer_status
-- description: this table lists the possible transfer statuses.
--

CREATE TABLE IF NOT EXISTS transfer_status (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  descr      TEXT NOT NULL,
  is_final   BOOLEAN NOT NULL,
  is_success BOOLEAN NOT NULL,
  UNIQUE (name)
);

-- Transfer Statuses
INSERT INTO transfer_status (name,descr,is_final,is_success) 
  VALUES
  ('pending','Newly created transfer request', FALSE, FALSE),
  ('clientApproved','Approved by loosing registrar', TRUE, TRUE),
  ('clientRejected','Rejected by loosing registrar',TRUE, FALSE),
  ('clientCancelled','Cancelled by gaining registrar', TRUE, FALSE),
  ('serverApproved','Approved by registry', TRUE, TRUE),
  ('serverCancelled','Cancelled by registry', TRUE, FALSE)
  ON CONFLICT DO NOTHING;

-- insert new job types for transfer processing
INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key
) 
VALUES
(
    'provision_domain_transfer_in_request',
    'Submits domain transfer request to the backend',
    'provision_domain_transfer_in_request',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_transfer_in',
    'Fetches transferred domain data',
    'provision_domain_transfer_in',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
)
ON CONFLICT DO NOTHING;

-- second step for item strategy for transfer domain order
INSERT INTO order_item_strategy(order_type_id,object_id,provision_order) VALUES
(
    (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_in'),
    tc_id_from_name('order_item_object','domain'),
    2
)
ON CONFLICT DO NOTHING;

DROP INDEX IF EXISTS order_item_transfer_in_domain_name_accreditation_tld_id_idx;
CREATE UNIQUE INDEX ON order_item_transfer_in_domain(name,accreditation_tld_id) 
  WHERE status_id = tc_id_from_name('order_item_status','pending') 
    OR status_id = tc_id_from_name('order_item_status','ready'); 


ALTER TABLE order_item_plan ADD COLUMN IF NOT EXISTS provision_order INT;

-- replace depth with provision_order
DROP FUNCTION IF EXISTS f_order_item_plan;
CREATE OR REPLACE FUNCTION f_order_item_plan(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                UUID,
                     id                      UUID,
                     parent_id               UUID,
                     order_item_id           UUID,
                     plan_status_id          UUID,
                     object_id               UUID,
                     plan_status_name        TEXT,
                     plan_status_is_success  BOOLEAN,
                     plan_status_is_final    BOOLEAN,
                     object_name             TEXT,
                     reference_id            UUID,
                     result_message          TEXT,
                     provision_order         INT,
                     parent_object_id        UUID
                 )
AS $$
BEGIN
    RETURN QUERY
        WITH RECURSIVE plan AS (
            SELECT
                order_item_plan.*,
                NULL::uuid   AS parent_object_id
            FROM order_item_plan
            WHERE order_item_plan.parent_id IS NULL AND order_item_plan.order_item_id = p_order_item_id
            union
            SELECT
                order_item_plan.*,
                plan.order_item_object_id as parent_object_id
            FROM order_item_plan
                     INNER JOIN plan on order_item_plan.parent_id = plan.id
            WHERE order_item_plan.order_item_id = p_order_item_id
        )
        SELECT
            oi.order_id AS order_id,
            p.id AS id,
            p.parent_id AS parent_id,
            p.order_item_id AS order_item_id,
            s.id AS plan_status_id,
            obj.id AS object_id,
            s.name AS plan_status_name,
            s.is_success AS plan_status_is_success,
            s.is_final AS plan_status_is_final,
            obj.name AS object_name,
            p.reference_id AS reference_id,
            p.result_message,
            p.provision_order,
            p.parent_object_id
        FROM plan p
                 JOIN order_item_object obj ON obj.id = p.order_item_object_id
                 JOIN order_item_plan_status s ON s.id = p.status_id
                 JOIN order_item oi ON oi.id = p.order_item_id
        ORDER BY p.provision_order ASC;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS f_order_item_plan_status;
CREATE OR REPLACE FUNCTION f_order_item_plan_status(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                UUID,
                     order_item_id           UUID,
                     provision_order         INT,
                     total                   BIGINT,
                     total_new               BIGINT,
                     total_success           BIGINT,
                     total_fail              BIGINT,
                     total_processing        BIGINT,
                     objects                 TEXT[],
                     object_ids              UUID[],
                     order_item_plan_ids     UUID[]
                 )
AS $$
BEGIN
    RETURN QUERY
        SELECT
            p.order_id,
            p.order_item_id,
            p.provision_order,
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE p.plan_status_name='new') AS total_new,
            COUNT(*) FILTER (WHERE p.plan_status_is_success AND p.plan_status_is_final) AS total_success,
            COUNT(*) FILTER (WHERE NOT p.plan_status_is_success AND p.plan_status_is_final ) AS total_fail,
            COUNT(*) FILTER (WHERE NOT p.plan_status_is_final AND p.plan_status_name != 'new' ) AS total_processing,
            ARRAY_AGG(p.object_name) AS objects,
            ARRAY_AGG(p.object_id) AS object_ids,
            ARRAY_AGG(p.id) AS order_item_plan_ids
        FROM f_order_item_plan(p_order_item_id) p
        GROUP BY 1,2,3
        ORDER BY p.provision_order ASC;
END;
$$ LANGUAGE plpgsql;

-- function: plan_transfer_in_domain_provision_domain()
-- description: responsible for creation of transfer in request and finalizing domain transfer
CREATE OR REPLACE FUNCTION plan_transfer_in_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in_domain        RECORD;
BEGIN

    SELECT * INTO v_transfer_in_domain
    FROM v_order_transfer_in_domain
    WHERE order_item_id = NEW.order_item_id;

    IF NEW.provision_order = 1 THEN

        -- first step in transfer_in processing
        -- request will be sent to registry
        INSERT INTO provision_domain_transfer_in_request(
            domain_name,
            pw,
            transfer_period,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            order_metadata,
            order_item_plan_ids
        ) VALUES(
            v_transfer_in_domain.domain_name,
            v_transfer_in_domain.auth_info,
            v_transfer_in_domain.transfer_period,
            v_transfer_in_domain.accreditation_id,
            v_transfer_in_domain.accreditation_tld_id,
            v_transfer_in_domain.tenant_customer_id,
            v_transfer_in_domain.order_metadata,
            ARRAY[NEW.id]
        );

    ELSIF NEW.provision_order = 2 THEN

        -- second step in transfer_in processing
        -- check if transfer was approved

        PERFORM FROM provision_domain_transfer_in_request pdt 
        JOIN transfer_in_domain_plan tidp ON tidp.parent_id = NEW.id
        JOIN transfer_status ts ON ts.id = pdt.transfer_status_id
        WHERE tidp.id = ANY(pdt.order_item_plan_ids) AND ts.is_final AND ts.is_success;

        IF NOT FOUND THEN
            UPDATE transfer_in_domain_plan
            SET status_id = tc_id_from_name('order_item_plan_status','failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END IF;

        -- fetch data from registry and provision domain entry
        INSERT INTO provision_domain_transfer_in(
            domain_name,
            pw,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            tags,
            metadata,
            order_metadata,
            order_item_plan_ids
        ) VALUES (
            v_transfer_in_domain.domain_name,
            v_transfer_in_domain.auth_info,
            v_transfer_in_domain.accreditation_id,
            v_transfer_in_domain.accreditation_tld_id,
            v_transfer_in_domain.tenant_customer_id,
            v_transfer_in_domain.tags,
            v_transfer_in_domain.metadata,
            v_transfer_in_domain.order_metadata,
            ARRAY[NEW.id]
        );

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_item_plan_start()
-- description: this is triggered when the order goes from new to pending
-- and is in charge of updating the items and setting status 'ready'
CREATE OR REPLACE FUNCTION order_item_plan_start() RETURNS TRIGGER AS $$
DECLARE
    v_strategy     RECORD;
BEGIN
    -- check to see if we are waiting for any other object

    SELECT * INTO v_strategy
    FROM f_order_item_plan_status(NEW.id)
    WHERE total_new > 0
    ORDER BY provision_order ASC LIMIT 1;

    IF FOUND THEN
        UPDATE order_item_plan
        SET status_id = tc_id_from_name('order_item_plan_status','processing')
        WHERE
            order_item_id=NEW.id
          AND status_id=tc_id_from_name('order_item_plan_status','new')
          AND order_item_object_id = ANY(v_strategy.object_ids)
          AND provision_order = v_strategy.provision_order;
    ELSE

        RAISE NOTICE 'order processing has ended';

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_item_plan_update()
CREATE OR REPLACE FUNCTION order_item_plan_update() RETURNS TRIGGER AS $$
DECLARE
    v_strategy      RECORD;
    v_new_strategy  RECORD;
BEGIN

    -- RAISE NOTICE 'placing lock on related rows...';

    PERFORM * FROM order_item_plan WHERE order_item_id = NEW.order_item_id FOR UPDATE;

    -- check to see if we are waiting for any other object
    SELECT * INTO v_strategy
    FROM f_order_item_plan_status(NEW.order_item_id)
    WHERE
        NEW.id = ANY(order_item_plan_ids)
    ORDER BY provision_order ASC LIMIT 1;


    IF v_strategy.total_fail > 0 THEN
        -- order item should be canceled immediately
        UPDATE order_item
        SET status_id = (SELECT id FROM order_item_status WHERE is_final AND NOT is_success)
        WHERE id = NEW.order_item_id AND status_id = tc_id_from_name('order_item_status','ready');

        -- cancel the rest of the plan as well
        UPDATE order_item_plan
        SET status_id = (SELECT id FROM order_item_plan_status WHERE is_final AND NOT is_success)
        WHERE
            order_item_id = NEW.order_item_id AND id <> NEW.id
          AND status_id = tc_id_from_name('order_item_plan_status','new');

        RAISE NOTICE 'at least one of the objects failed item canceled';
        RETURN NEW;
    END IF;

    -- if no failures, we need to check and see if there's anything pending
    IF v_strategy.total_processing > 0 THEN
        -- RAISE NOTICE 'Waiting. for other objects to complete (id: %s) remaining: %',NEW.id,v_strategy.total_processing;
        RETURN NEW;
    END IF;

    IF v_strategy.total_success = v_strategy.total THEN

        SELECT *
        INTO v_new_strategy
        FROM f_order_item_plan_status(NEW.order_item_id)
        WHERE total_new > 0
        ORDER BY provision_order ASC LIMIT 1;

        IF NOT FOUND THEN

            -- nothing more to do, we can mark the order as complete!
            UPDATE order_item
            SET status_id = (SELECT id FROM order_item_status WHERE is_final AND is_success)
            WHERE id = NEW.order_item_id AND status_id = tc_id_from_name('order_item_status','ready');

        ELSE

            -- this should trigger the provisioning of the objects on the next object group
            UPDATE order_item_plan
            SET status_id = tc_id_from_name('order_item_plan_status','processing')
            WHERE
                order_item_id=NEW.order_item_id
              AND status_id=tc_id_from_name('order_item_plan_status','new')
              AND order_item_object_id = ANY(v_new_strategy.object_ids);

            RAISE NOTICE 'Order %: processing objects of type %',v_new_strategy.order_id,v_new_strategy.objects;

        END IF;

    END IF;

    RAISE NOTICE 'nothing else to do';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_order_item()
-- description: creates the plan for registering a domain name
CREATE OR REPLACE FUNCTION plan_order_item() RETURNS TRIGGER AS $$
DECLARE
    v_object            RECORD;
    v_order             RECORD;
    v_accreditation_tld RECORD;
    v_previous_id       UUID;
    v_previous_rank     INT DEFAULT 1;
    v_previous_parent   UUID;
    v_parent            UUID;
    v_related_obj       RECORD;
BEGIN

    -- load the order
    SELECT * INTO v_order FROM "order" WHERE id=NEW.order_id;

    -- load accreditation
    SELECT * INTO v_accreditation_tld FROM v_accreditation_tld WHERE accreditation_tld_id = NEW.accreditation_tld_id;

    -- loop through the strategy to create a plan
    FOR v_object IN SELECT
                                RANK() OVER (ORDER BY provision_order DESC) AS rank,
                                object_name,
                                object_id,
                                provision_order,
                                product_name,
                                order_type_name
                    FROM v_provider_instance_order_item_strategy
                    WHERE
                        provider_instance_id=v_accreditation_tld.provider_instance_id
                      AND order_type_id = v_order.type_id
                    ORDER BY 1
        LOOP

            IF v_previous_id IS NOT NULL THEN
                IF v_object.rank = v_previous_rank THEN
                    v_parent := v_previous_parent;
                ELSE
                    v_parent := v_previous_id;
                END IF;
            END IF;

            FOR v_related_obj IN SELECT * FROM v_order_item_plan_object
                                 WHERE order_item_id = NEW.id
                                   AND object_id=v_object.object_id
                LOOP

                    EXECUTE FORMAT('INSERT INTO %s_%s_plan(
          order_item_id,
          parent_id,
          order_item_object_id,
          reference_id,
          provision_order
        )
        VALUES ($1,$2,$3,$4,$5)
        RETURNING id',v_object.order_type_name,v_object.product_name)
                        INTO v_previous_id
                        USING
                            NEW.id,
                            v_parent,
                            v_object.object_id,
                            v_related_obj.id,
                            v_object.provision_order;

                END LOOP;

            v_previous_rank := v_object.rank;
            v_previous_parent := v_parent;

        END LOOP;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


-- function: plan_simple_order_item()
-- description: creates the plan for an order item not related to a tld (not referring to accreditations and providers)
CREATE OR REPLACE FUNCTION plan_simple_order_item() RETURNS TRIGGER AS $$
DECLARE
    v_object            RECORD;
    v_order             RECORD;
    v_previous_id       UUID;
    v_previous_rank     INT DEFAULT 1;
    v_previous_parent   UUID;
    v_parent            UUID;
    v_related_obj       RECORD;
BEGIN

    -- load the order
    SELECT * INTO v_order FROM "order" WHERE id=NEW.order_id;

    -- loop through the strategy to create a plan
    FOR v_object IN SELECT
                                RANK() OVER (ORDER BY provision_order DESC) AS rank,
                                object_name,
                                object_id,
                                provision_order,
                                product_name,
                                order_type_name
                    FROM v_order_item_strategy
                    WHERE
                        order_type_id = v_order.type_id
                    ORDER BY 1
        LOOP

            IF v_previous_id IS NOT NULL THEN
                IF v_object.rank = v_previous_rank THEN
                    v_parent := v_previous_parent;
                ELSE
                    v_parent := v_previous_id;
                END IF;
            END IF;

            FOR v_related_obj IN SELECT * FROM v_order_item_plan_object
                                 WHERE order_item_id = NEW.id
                                   AND object_id=v_object.object_id
                LOOP

                    EXECUTE FORMAT('INSERT INTO %s_%s_plan(
          order_item_id,
          parent_id,
          order_item_object_id,
          reference_id,
          provision_order
        )
        VALUES ($1,$2,$3,$4,$5)
        RETURNING id',v_object.order_type_name,v_object.product_name)
                        INTO v_previous_id
                        USING
                            NEW.id,
                            v_parent,
                            v_object.object_id,
                            v_related_obj.id,
                            v_object.provision_order;

                END LOOP;

            v_previous_rank := v_object.rank;
            v_previous_parent := v_parent;

        END LOOP;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

-- dropped in favor of unique index constraint
DROP TRIGGER IF EXISTS order_prevent_multiple_processing_transfers_tg ON order_item_transfer_in_domain;
DROP FUNCTION IF EXISTS order_prevent_multiple_processing_transfers;

ALTER TABLE IF EXISTS order_item_transfer_in_domain ADD COLUMN IF NOT EXISTS tags TEXT[];
ALTER TABLE IF EXISTS order_item_transfer_in_domain ADD COLUMN IF NOT EXISTS metadata JSONB;

CREATE TABLE IF NOT EXISTS transfer_in_domain_plan(
  PRIMARY KEY(id),
  FOREIGN KEY (order_item_id) REFERENCES order_item_transfer_in_domain
) INHERITS(order_item_plan,class.audit_trail);

DROP TRIGGER IF EXISTS plan_transfer_in_domain_provision_domain_tg ON transfer_in_domain_plan;
CREATE TRIGGER plan_transfer_in_domain_provision_domain_tg 
  AFTER UPDATE ON transfer_in_domain_plan 
  FOR EACH ROW WHEN ( 
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('order_item_plan_status','processing')
   AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain') 
  )
  EXECUTE PROCEDURE plan_transfer_in_domain_provision_domain();

DROP TRIGGER IF EXISTS order_item_plan_update_tg ON transfer_in_domain_plan;
CREATE TRIGGER order_item_plan_update_tg
  AFTER UPDATE ON transfer_in_domain_plan
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id 
    AND OLD.status_id = tc_id_from_name('order_item_plan_status','processing')
  )
  EXECUTE PROCEDURE order_item_plan_update();

-- adding order_item_transfer_in_domain to this view
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
  d.id AS id
FROM order_item_transfer_in_domain d
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

-- adding tags and metadata
CREATE OR REPLACE VIEW v_order_transfer_in_domain AS 
SELECT
  tid.id AS order_item_id,
  tid.order_id AS order_id,
  tid.accreditation_tld_id,
  o.metadata AS order_metadata,
  o.tenant_customer_id,
  o.type_id,
  o.customer_user_id,
  o.status_id,
  s.name AS status_name,
  s.descr AS status_descr,
  s.is_final AS status_is_final,
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
  tid.name AS domain_name,
  tid.transfer_period,
  tid.auth_info,
  tid.tags,
  tid.metadata
FROM order_item_transfer_in_domain tid
  JOIN "order" o ON o.id=tid.order_id
  JOIN v_order_type ot ON ot.id = o.type_id
  JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
  JOIN order_status s ON s.id = o.status_id
  JOIN v_accreditation_tld at ON at.accreditation_tld_id = tid.accreditation_tld_id
;

--
-- table: provision_domain_transfer_in_request
-- description: this table is used to create and track transfer in request
--

CREATE TABLE provision_domain_transfer_in_request (
  domain_name             FQDN NOT NULL,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
  pw                      TEXT,
  transfer_period         INT NOT NULL DEFAULT 1,
  transfer_status_id      UUID NOT NULL DEFAULT tc_id_from_name('transfer_status','pending') 
                          REFERENCES transfer_status,
  requested_by            TEXT,
  requested_date          TIMESTAMPTZ,
  action_by               TEXT,
  action_date             TIMESTAMPTZ,
  expiry_date             TIMESTAMPTZ,
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);

--
-- table: provision_domain_transfer_in
-- description: this table is used to finalize transfer_in domain provisioning
--

CREATE TABLE IF NOT EXISTS provision_domain_transfer_in (
  domain_name             FQDN NOT NULL,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
  pw                      TEXT,
  ry_created_date         TIMESTAMPTZ,
  ry_expiry_date          TIMESTAMPTZ,
  ry_updated_date         TIMESTAMPTZ,
  ry_transfered_date      TIMESTAMPTZ,
  hosts                   FQDN[],
  tags                    TEXT[],
  metadata                JSONB,
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer,
  PRIMARY KEY(id)
) INHERITS (class.audit_trail,class.provision);


-- function: provision_domain_success()
-- description: complete or continue provision order based on the status
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_success() RETURNS TRIGGER AS $$
BEGIN
    -- domain
    INSERT INTO domain(
        id,
        tenant_customer_id,
        accreditation_tld_id,
        name,
        auth_info,
        roid,
        ry_created_date,
        ry_expiry_date,
        expiry_date,
        ry_updated_date,
        ry_transfered_date,
        tags,
        metadata
    ) (
        SELECT
            pdt.id,    -- domain id
            pdt.tenant_customer_id,
            pdt.accreditation_tld_id,
            pdt.domain_name,
            pdt.pw,
            pdt.roid,
            pdt.ry_created_date,
            pdt.ry_expiry_date,
            pdt.ry_expiry_date,
            pdt.updated_date,
            pdt.ry_transfered_date,
            pdt.tags,
            pdt.metadata
        FROM provision_domain_transfer_in pdt
        WHERE id = NEW.id
    );

    -- add linked hosts
    WITH new_host AS (
        INSERT INTO host(
            tenant_customer_id,
            name
        )
        SELECT NEW.tenant_customer_id, * FROM UNNEST(NEW.hosts) AS name
        ON CONFLICT (tenant_customer_id,name) DO UPDATE SET name = EXCLUDED.name
        RETURNING id
    ) INSERT INTO domain_host(
        domain_id,
        host_id
    ) SELECT NEW.id, id FROM new_host;

    -- rgp status
    INSERT INTO domain_rgp_status(
        domain_id,
        status_id
    ) VALUES (
        NEW.id,
        tc_id_from_name('rgp_status', 'transfer_grace_period')
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_domain_transfer_in_request_job()
-- description: creates the job to submit transfer request for the domain
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_request_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in   RECORD;
BEGIN

    SELECT
        NEW.id AS provision_domain_transfer_in_request_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.pw,
        pdt.transfer_period,
        pdt.order_metadata AS metadata
    INTO v_transfer_in
    FROM provision_domain_transfer_in_request pdt
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pdt.id = NEW.id;

    UPDATE provision_domain_transfer_in_request SET job_id=job_submit(
        v_transfer_in.tenant_customer_id,
        'provision_domain_transfer_in_request',
        NEW.id,
        TO_JSONB(v_transfer_in.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_domain_transfer_in_job()
-- description: creates the job to fetch transferred domain data
CREATE OR REPLACE FUNCTION provision_domain_transfer_in_job() RETURNS TRIGGER AS $$
DECLARE
    v_transfer_in   RECORD;
BEGIN

    SELECT
        NEW.id AS provision_domain_transfer_in_id,
        tnc.id AS tenant_customer_id,
        TO_JSONB(a.*) AS accreditation,
        pdt.domain_name,
        pdt.order_metadata AS metadata
    INTO v_transfer_in
    FROM provision_domain_transfer_in pdt
             JOIN v_accreditation a ON  a.accreditation_id = NEW.accreditation_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE pdt.id = NEW.id;

    UPDATE provision_domain_transfer_in SET job_id=job_submit(
        v_transfer_in.tenant_customer_id,
        'provision_domain_transfer_in',
        NEW.id,
        TO_JSONB(v_transfer_in.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS provision_domain_transfer_in_request_job_tg ON provision_domain_transfer_in_request;
CREATE TRIGGER provision_domain_transfer_in_request_job_tg
  AFTER INSERT ON provision_domain_transfer_in_request
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_transfer_in_request_job();

DROP TRIGGER IF EXISTS provision_domain_transfer_in_job_tg ON provision_domain_transfer_in;
CREATE TRIGGER provision_domain_transfer_in_job_tg
  AFTER INSERT ON provision_domain_transfer_in
  FOR EACH ROW WHEN (
    NEW.status_id = tc_id_from_name('provision_status', 'pending') 
  ) EXECUTE PROCEDURE provision_domain_transfer_in_job();

DROP TRIGGER IF EXISTS provision_domain_transfer_in_success_tg ON provision_domain_transfer_in;
CREATE TRIGGER provision_domain_transfer_in_success_tg
  AFTER UPDATE ON provision_domain_transfer_in
  FOR EACH ROW WHEN (
    OLD.status_id <> NEW.status_id
    AND NEW.status_id = tc_id_from_name('provision_status','completed')
  ) EXECUTE PROCEDURE provision_domain_transfer_in_success();

\i triggers.ddl
\i provisioning/triggers.ddl