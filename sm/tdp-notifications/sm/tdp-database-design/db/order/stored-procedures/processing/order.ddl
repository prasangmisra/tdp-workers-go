
-- function: order_item_plan_fail()
-- description: this function updates all order item plans and order item as failed
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

-- function: order_item_plan_start()
-- description: this is triggered when the order goes from new to pending
-- and is in charge of updating the items and setting status 'processing'
-- only if all order item plans are ready (no validation needed)
CREATE OR REPLACE FUNCTION order_item_plan_start() RETURNS TRIGGER AS $$
DECLARE
    v_strategy      RECORD;
BEGIN

    -- start validation if needed
    UPDATE order_item_plan 
    SET validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'started')
    WHERE order_item_id = NEW.id
        AND validation_status_id = tc_id_from_name('order_item_plan_validation_status', 'pending');

    IF NOT FOUND THEN
        -- start plan execution if nothing to validate

        SELECT * INTO v_strategy
        FROM f_order_item_plan_status(NEW.id)
        WHERE total_new > 0
        LIMIT 1;

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

    PERFORM * FROM order_item WHERE id = NEW.order_item_id FOR UPDATE;

    IF NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','failed') THEN

        WITH job_data AS (
            SELECT result_data, result_message
            FROM job
            WHERE reference_id = NEW.id
            LIMIT 1
        )
        UPDATE order_item_plan
        SET
            result_data = job_data.result_data,
            result_message = COALESCE(job_data.result_message, order_item_plan.result_message)
        FROM job_data
        WHERE order_item_plan.id = NEW.id;

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
        LIMIT 1;

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

    PERFORM * FROM order_item WHERE id = NEW.order_item_id FOR UPDATE;

    -- check to see if we are waiting for any other object
    SELECT * INTO v_strategy
    FROM f_order_item_plan_status(NEW.order_item_id)
    WHERE
        NEW.id = ANY(order_item_plan_ids)
    LIMIT 1;


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
        LIMIT 1;

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
