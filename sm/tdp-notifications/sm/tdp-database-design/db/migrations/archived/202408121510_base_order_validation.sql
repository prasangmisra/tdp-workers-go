ALTER TABLE order_item_strategy ADD COLUMN IF NOT EXISTS is_validation_required BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS order_item_plan_validation_status(
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name                  TEXT NOT NULL UNIQUE,
  descr                 TEXT,
  is_success            BOOLEAN NOT NULL,
  is_final              BOOLEAN NOT NULL
) INHERITS(class.audit);

DROP INDEX IF EXISTS order_item_plan_validation_status_is_success_is_final_idx;
CREATE UNIQUE INDEX ON order_item_plan_validation_status(is_success,is_final) WHERE is_final;

INSERT INTO order_item_plan_validation_status(name,descr,is_success,is_final)
  VALUES
    ('pending','validation pending, waiting completion',TRUE,FALSE),
    ('completed','validation succeeded',TRUE,TRUE),
    ('failed','validation failed',FALSE,TRUE)
  ON CONFLICT DO NOTHING;

ALTER TABLE order_item_plan
ADD COLUMN IF NOT EXISTS validation_status_id UUID NOT NULL REFERENCES order_item_plan_validation_status
DEFAULT tc_id_from_name('order_item_plan_validation_status','pending');

DROP FUNCTION f_order_item_plan;
CREATE OR REPLACE FUNCTION f_order_item_plan(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                       UUID,
                     id                             UUID,
                     parent_id                      UUID,
                     order_item_id                  UUID,
                     plan_status_id                 UUID,
                     object_id                      UUID,
                     plan_status_name               TEXT,
                     plan_status_is_success         BOOLEAN,
                     plan_status_is_final           BOOLEAN,
                     plan_validation_status_name    TEXT,
                     object_name                    TEXT,
                     reference_id                   UUID,
                     result_message                 TEXT,
                     provision_order                INT,
                     parent_object_id               UUID
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
            vs.name AS plan_validation_status_name,
            obj.name AS object_name,
            p.reference_id AS reference_id,
            p.result_message,
            p.provision_order,
            p.parent_object_id
        FROM plan p
                 JOIN order_item_object obj ON obj.id = p.order_item_object_id
                 JOIN order_item_plan_status s ON s.id = p.status_id
                 JOIN order_item_plan_validation_status vs ON vs.id = p.validation_status_id
                 JOIN order_item oi ON oi.id = p.order_item_id
        ORDER BY p.provision_order ASC;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION f_order_item_plan_status;
CREATE OR REPLACE FUNCTION f_order_item_plan_status(p_order_item_id UUID)
    RETURNS TABLE(
                     order_id                UUID,
                     order_item_id           UUID,
                     provision_order         INT,
                     total                   BIGINT,
                     total_new               BIGINT,
                     total_validated         BIGINT, 
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
            COUNT(*) FILTER (WHERE p.plan_validation_status_name='completed') AS total_validated,
            COUNT(*) FILTER (WHERE p.plan_status_is_success AND p.plan_status_is_final) AS total_success,
            COUNT(*) FILTER (WHERE NOT p.plan_status_is_success AND p.plan_status_is_final ) AS total_fail,
            COUNT(*) FILTER (WHERE p.plan_status_name='processing' ) AS total_processing,
            ARRAY_AGG(p.object_name) AS objects,
            ARRAY_AGG(p.object_id) AS object_ids,
            ARRAY_AGG(p.id) AS order_item_plan_ids
        FROM f_order_item_plan(p_order_item_id) p
        GROUP BY 1,2,3
        ORDER BY p.provision_order ASC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION order_item_plan_fail(p_order_item_id UUID) RETURNS VOID AS $$
BEGIN

    UPDATE order_item
    SET status_id = (SELECT id FROM order_item_status WHERE is_final AND NOT is_success)
    WHERE id = p_order_item_id AND status_id = tc_id_from_name('order_item_status','ready');

    -- cancel the rest of the plan as well
    UPDATE order_item_plan
    SET status_id = (SELECT id FROM order_item_plan_status WHERE is_final AND NOT is_success)
    WHERE
        order_item_id = p_order_item_id
        AND status_id = tc_id_from_name('order_item_plan_status','new');

    RAISE NOTICE 'at least one of the objects failed validation item canceled';

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION order_item_plan_start() RETURNS TRIGGER AS $$
DECLARE
    is_validated    BOOLEAN;
    v_strategy      RECORD;
BEGIN
    SELECT SUM(total_validated) = SUM(total)
    INTO is_validated
    FROM f_order_item_plan_status(NEW.id);

    IF is_validated THEN
        -- start plan execution if everything was validated

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

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: order_item_plan_ready()
CREATE OR REPLACE FUNCTION order_item_plan_validated() RETURNS TRIGGER AS $$
DECLARE
    is_validated    BOOLEAN;
    v_strategy      RECORD;
BEGIN

    PERFORM * FROM order_item_plan WHERE order_item_id = NEW.order_item_id FOR UPDATE;

    IF NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','failed') THEN

        UPDATE order_item_plan
        SET
            result_data=(SELECT result_data FROM job WHERE reference_id=NEW.id),
            result_message=COALESCE((SELECT result_message FROM job WHERE reference_id=NEW.id), result_message)
        WHERE id = NEW.id;

        -- fail order if at least one plan item failed
        PERFORM order_item_plan_fail(NEW.order_item_id);

        RETURN NEW;
    END IF;

    SELECT SUM(total_validated) = SUM(total)
    INTO is_validated
    FROM f_order_item_plan_status(NEW.order_item_id);

    IF is_validated THEN
        -- start processing of plan if everything is validated

        SELECT * INTO v_strategy
        FROM f_order_item_plan_status(NEW.order_item_id)
        WHERE total_new > 0
        ORDER BY provision_order ASC LIMIT 1;

        IF FOUND THEN
            UPDATE order_item_plan
            SET status_id = tc_id_from_name('order_item_plan_status','processing')
            WHERE
                order_item_id=NEW.order_item_id
            AND status_id=tc_id_from_name('order_item_plan_status','new')
            AND order_item_object_id = ANY(v_strategy.object_ids)
            AND provision_order = v_strategy.provision_order;
        ELSE

            -- nothing to do after validation; everything was skipped
            UPDATE order_item
            SET status_id = (SELECT id FROM order_item_status WHERE is_final AND is_success)
            WHERE id = NEW.order_item_id AND status_id = tc_id_from_name('order_item_status','ready');

        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_item_plan_processed()
CREATE OR REPLACE FUNCTION order_item_plan_processed() RETURNS TRIGGER AS $$
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
        -- fail order if at least one plan item failed

        PERFORM order_item_plan_fail(NEW.order_item_id);

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
    v_object                RECORD;
    v_order                 RECORD;
    v_accreditation_tld     RECORD;
    v_previous_id           UUID;
    v_previous_rank         INT DEFAULT 1;
    v_previous_parent       UUID;
    v_parent                UUID;
    v_related_obj           RECORD;
    v_plan_init_status_id   UUID;
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
                                order_type_name,
                                is_validation_required
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
          provision_order,
          validation_status_id
        )
        VALUES ($1,$2,$3,$4,$5,$6)
        RETURNING id',v_object.order_type_name,v_object.product_name)
                        INTO v_previous_id
                        USING
                            NEW.id,
                            v_parent,
                            v_object.object_id,
                            v_related_obj.id,
                            v_object.provision_order,
                            CASE WHEN v_object.is_validation_required THEN 
                                tc_id_from_name('order_item_plan_validation_status', 'pending')
                            ELSE
                                tc_id_from_name('order_item_plan_validation_status', 'completed')
                            END;

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
                                order_type_name,
                                is_validation_required
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
          provision_order,
          validation_status_id
        )
        VALUES ($1,$2,$3,$4,$5,$6)
        RETURNING id',v_object.order_type_name,v_object.product_name)
                        INTO v_previous_id
                        USING
                            NEW.id,
                            v_parent,
                            v_object.object_id,
                            v_related_obj.id,
                            v_object.provision_order,
                            CASE WHEN v_object.is_validation_required THEN 
                                tc_id_from_name('order_item_plan_validation_status', 'pending')
                            ELSE
                                tc_id_from_name('order_item_plan_validation_status', 'completed')
                            END;

                END LOOP;

            v_previous_rank := v_object.rank;
            v_previous_parent := v_parent;

        END LOOP;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

DROP VIEW IF EXISTS v_provider_instance_order_item_strategy;
CREATE OR REPLACE VIEW v_provider_instance_order_item_strategy AS 
    -- default strategy
    WITH default_strategy AS (
        SELECT 
            t.id AS type_id,
            o.id AS object_id,
            s.provision_order,
            s.is_validation_required
        FROM order_item_strategy s 
            JOIN order_item_object o ON o.id = s.object_id
            JOIN order_type t ON t.id = s.order_type_id
        WHERE s.provider_instance_id IS NULL
    )
    SELECT 
        p.name      AS provider_name,
        p.id        AS provider_id,
        pi.id       AS provider_instance_id,
        pi.name     AS provider_instance_name,
        dob.name    AS object_name,
        dob.id      AS object_id,
        ot.id       AS order_type_id,
        ot.name     AS order_type_name,
        prod.id        AS product_id,
        prod.name      AS product_name,
        COALESCE(s.provision_order,ds.provision_order) AS provision_order,
        CASE WHEN s.id IS NULL THEN TRUE ELSE FALSE END AS is_default,
        COALESCE(s.is_validation_required, ds.is_validation_required) AS is_validation_required
    FROM provider_instance pi 
        JOIN default_strategy ds ON TRUE
        JOIN provider p ON p.id = pi.provider_id
        JOIN order_item_object dob ON dob.id = ds.object_id 
        JOIN order_type ot ON ds.type_id = ot.id
        JOIN product prod ON prod.id = ot.product_id 
        LEFT JOIN order_item_strategy s
            ON  s.provider_instance_id = pi.id 
                AND ot.id = s.order_type_id 
                AND s.object_id = dob.id
    ORDER BY 1,4,5,7;
;

DROP VIEW IF EXISTS v_order_item_strategy;
CREATE OR REPLACE VIEW v_order_item_strategy AS 
    -- default strategy
    WITH default_strategy AS (
        SELECT 
            t.id AS type_id,
            o.id AS object_id,
            s.provision_order,
            s.is_validation_required
        FROM order_item_strategy s 
            JOIN order_item_object o ON o.id = s.object_id
            JOIN order_type t ON t.id = s.order_type_id
        WHERE s.provider_instance_id IS NULL
    )
    SELECT 
        dob.name    AS object_name,
        dob.id      AS object_id,
        ot.id       AS order_type_id,
        ot.name     AS order_type_name,
        prod.id        AS product_id,
        prod.name      AS product_name,
        COALESCE(s.provision_order,ds.provision_order) AS provision_order,
        CASE WHEN s.id IS NULL THEN TRUE ELSE FALSE END AS is_default,
        COALESCE(s.is_validation_required, ds.is_validation_required) AS is_validation_required
    FROM default_strategy ds
        JOIN order_item_object dob ON dob.id = ds.object_id 
        JOIN order_type ot ON ds.type_id = ot.id
        JOIN product prod ON prod.id = ot.product_id 
        LEFT JOIN order_item_strategy s
            ON  ot.id = s.order_type_id 
                AND s.object_id = dob.id
    ORDER BY 1,4,5,7;
;
