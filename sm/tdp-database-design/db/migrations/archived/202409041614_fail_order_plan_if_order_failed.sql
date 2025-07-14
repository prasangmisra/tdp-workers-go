CREATE OR REPLACE FUNCTION order_on_failed() RETURNS TRIGGER AS $$
BEGIN

    UPDATE order_item
    SET status_id = tc_id_from_name('order_item_status', 'canceled')
    WHERE order_id = NEW.id;

    UPDATE order_item_plan oip
    SET status_id = tc_id_from_name('order_item_plan_status', 'failed')
    FROM order_item oi
    WHERE oi.order_id = NEW.id AND oip.order_item_id = oi.id;


    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS order_on_failed_tg ON "order";
CREATE OR REPLACE TRIGGER order_on_failed_tg
    AFTER UPDATE ON "order"
    FOR EACH ROW WHEN (OLD.status_id <> NEW.status_id AND NEW.status_id = tc_id_from_name('order_status','failed'))
EXECUTE PROCEDURE order_on_failed();
