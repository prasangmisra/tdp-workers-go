-- Changes the way of obtaining plan items by looking for only specific order item
-- Improves performance as previously the recursive view was recalculated 4 times during one order processing.

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
    depth                   INT,
    parent_object_id        UUID
)
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE plan AS (
        SELECT
            order_item_plan.*,
            NULL::uuid   AS parent_object_id,
            0            AS depth
        FROM order_item_plan
        WHERE order_item_plan.parent_id IS NULL AND order_item_plan.order_item_id = p_order_item_id
        union
        SELECT
            order_item_plan.*,
            plan.order_item_object_id as parent_object_id,
            plan.depth + 1
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
        p.depth,
        p.parent_object_id
    FROM plan p
    JOIN order_item_object obj ON obj.id = p.order_item_object_id
    JOIN order_item_plan_status s ON s.id = p.status_id
    JOIN order_item oi ON oi.id = p.order_item_id
    ORDER BY p.depth DESC;
END;
$$ LANGUAGE plpgsql;


--
-- f_order_item_plan_status: simulates parametarized view 
-- gets a status summary for all order_item_plan records for a given order item 
--

CREATE OR REPLACE FUNCTION f_order_item_plan_status(p_order_item_id UUID)
RETURNS TABLE(
    order_id                UUID,
    order_item_id           UUID,
    depth                   INT,
    total                   BIGINT,
    total_new               BIGINT,
    total_success           BIGINT,
    total_fail              BIGINT,
    total_processing        BIGINT,
    objects                 TEXT[],
    object_ids              UUID[]
)
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.order_id,
        p.order_item_id,
        p.depth,
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE p.plan_status_name='new') AS total_new,
        COUNT(*) FILTER (WHERE p.plan_status_is_success AND p.plan_status_is_final) AS total_success,
        COUNT(*) FILTER (WHERE NOT p.plan_status_is_success AND p.plan_status_is_final ) AS total_fail,
        COUNT(*) FILTER (WHERE NOT p.plan_status_is_final AND p.plan_status_name != 'new' ) AS total_processing,
        ARRAY_AGG(p.object_name) AS objects,
        ARRAY_AGG(p.object_id) AS object_ids
    FROM f_order_item_plan(p_order_item_id) p
    GROUP BY 1,2,3
    ORDER BY p.depth DESC;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION build_order_notification_payload(_order_id UUID) RETURNS JSONB AS $$
DECLARE
  _payload      JSONB;
BEGIN
  SELECT 
    JSONB_BUILD_OBJECT(
      'order_id', oi.order_id,
      'order_status_name', vo.order_status_name,
      'order_item_plans', JSON_AGG(
        JSONB_BUILD_OBJECT(
          'object', p.object_name,
          'status', p.plan_status_name,
          'error', p.result_message
        )
      )
    )
  INTO _payload
  FROM order_item oi
  JOIN f_order_item_plan(oi.id) p ON TRUE
  JOIN v_order vo ON vo.order_id = oi.order_id 
  WHERE oi.order_id = _order_id
  GROUP BY oi.order_id, vo.order_status_name;

  RETURN _payload;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION order_item_plan_start() RETURNS TRIGGER AS $$
DECLARE
  v_strategy     RECORD;
BEGIN
  -- check to see if we are waiting for any other object

  SELECT * INTO v_strategy 
    FROM f_order_item_plan_status(NEW.id)
    WHERE total_new > 0 
    ORDER BY depth DESC LIMIT 1;

  IF FOUND THEN 
    UPDATE order_item_plan 
        SET status_id = tc_id_from_name('order_item_plan_status','processing') 
      WHERE 
        order_item_id=NEW.id 
        AND status_id=tc_id_from_name('order_item_plan_status','new')
        AND order_item_object_id = ANY(v_strategy.object_ids);
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
      NEW.order_item_object_id = ANY(object_ids)
    ORDER BY depth DESC LIMIT 1;


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
    ORDER BY depth DESC LIMIT 1;

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

DROP VIEW IF EXISTS v_order_item_plan_status;
DROP VIEW IF EXISTS v_order_item_plan;
