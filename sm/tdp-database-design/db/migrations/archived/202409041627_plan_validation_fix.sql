DROP TRIGGER IF EXISTS validate_create_domain_plan_tg ON create_domain_plan;
CREATE TRIGGER validate_create_domain_plan_tg
    AFTER UPDATE ON create_domain_plan
    FOR EACH ROW WHEN (
      OLD.validation_status_id <> NEW.validation_status_id
      AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','domain')
    )
    EXECUTE PROCEDURE validate_create_domain_plan();

DROP TRIGGER IF EXISTS validate_create_domain_host_plan_tg ON create_domain_plan;
CREATE TRIGGER validate_create_domain_host_plan_tg
    AFTER UPDATE ON create_domain_plan
    FOR EACH ROW WHEN (
      OLD.validation_status_id <> NEW.validation_status_id
      AND NEW.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
      AND NEW.order_item_object_id = tc_id_from_name('order_item_object','host')
    )
    EXECUTE PROCEDURE validate_create_domain_host_plan();


DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON create_contact_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_contact_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON create_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON create_host_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_host_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON create_hosting_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON create_hosting_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON delete_contact_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_contact_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON delete_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON delete_hosting_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON delete_hosting_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON redeem_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON redeem_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON renew_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON renew_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON transfer_in_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON transfer_in_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON update_contact_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_contact_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON update_domain_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_domain_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON update_host_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_host_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

DROP TRIGGER IF EXISTS order_item_plan_validated_tg ON update_hosting_plan;
CREATE TRIGGER order_item_plan_validated_tg
  AFTER UPDATE ON update_hosting_plan
  FOR EACH ROW WHEN (
    OLD.validation_status_id <> NEW.validation_status_id 
    AND OLD.validation_status_id = tc_id_from_name('order_item_plan_validation_status','started')
  )
  EXECUTE PROCEDURE order_item_plan_validated();

INSERT INTO order_item_plan_validation_status(name,descr,is_success,is_final)
  VALUES
    ('started','validation started, waiting completion',TRUE,FALSE)
ON CONFLICT DO NOTHING;

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


