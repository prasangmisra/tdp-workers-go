UPDATE job_type 
SET 
	reference_table=NULL,
    reference_status_table=NULL,
    reference_status_column='status_id'
WHERE 
	name = 'validate_host_available';

CREATE OR REPLACE FUNCTION order_item_plan_validated() RETURNS TRIGGER AS $$
DECLARE
    is_validated    BOOLEAN;
    v_strategy      RECORD;
BEGIN

    PERFORM * FROM order_item WHERE id = NEW.order_item_id FOR UPDATE;

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

    PERFORM * FROM order_item WHERE id = NEW.order_item_id FOR UPDATE;

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

CREATE OR REPLACE FUNCTION validate_add_secdns_does_not_exist() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.ds_data_id IS NOT NULL THEN
        -- we only need to check ds_data table and not child key_data because
        -- ds_data is generated from key_data
        PERFORM 1 FROM secdns_ds_data 
        WHERE id = (
            SELECT ds_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND digest = (SELECT digest FROM order_secdns_ds_data WHERE id = NEW.ds_data_id);

        IF FOUND THEN
            RAISE EXCEPTION 'SecDNS DS record to be added already exists';
        END IF;

    ELSE
        PERFORM 1 FROM secdns_key_data
        WHERE id = (
            SELECT key_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND public_key = (SELECT public_key FROM order_secdns_key_data WHERE id = NEW.key_data_id);

        IF FOUND THEN
            RAISE EXCEPTION 'SecDNS key record to be added already exists';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
