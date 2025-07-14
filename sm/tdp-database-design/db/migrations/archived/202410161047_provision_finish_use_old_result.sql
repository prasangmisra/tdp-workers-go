CREATE OR REPLACE FUNCTION provision_finish() RETURNS TRIGGER AS $$
DECLARE
    v_status      RECORD;
    v_oi_plan_id   UUID;
BEGIN

    SELECT * INTO v_status FROM provision_status WHERE id = NEW.status_id;

    IF NOT v_status.is_final THEN
        RETURN NEW;
    END IF;

    -- notify all the order_item_plan_ids that are pending
    IF NEW.order_item_plan_ids IS NOT NULL THEN

        FOR v_oi_plan_id IN SELECT UNNEST(NEW.order_item_plan_ids) AS id
            LOOP
                UPDATE order_item_plan
                SET
                    status_id = (
                        SELECT
                            id
                        FROM order_item_plan_status
                        WHERE is_success = v_status.is_success AND is_final
                    ),
                    result_data = COALESCE((NEW.result_data), (SELECT result_data FROM job WHERE id=NEW.job_id)),
                    result_message = COALESCE((NEW.result_message), (SELECT result_message FROM job WHERE id=NEW.job_id))
                WHERE id = v_oi_plan_id;
            END LOOP;

    END IF;

    IF v_status.is_success THEN
        EXECUTE 'UPDATE ' || TG_TABLE_NAME || ' SET provisioned_date=NOW() WHERE id = $1'
            USING NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
