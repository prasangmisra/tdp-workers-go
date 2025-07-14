-- function: order_item_prevent_insert()
-- description: avoids writing directly to order_item, it should all be done
-- through the child tables
CREATE OR REPLACE FUNCTION order_item_prevent_insert() RETURNS TRIGGER AS $$
DECLARE
    _pi     RECORD;
BEGIN

    SELECT * INTO _pi FROM v_order_product_type WHERE type_id = NEW.item_type_id;

    RAISE EXCEPTION 'MUST NOT insert in this table directly, for this product/order type (%/%) please use % instead',_pi.product_name,_pi.type_name,_pi.rel_name;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION order_item_prevent_insert IS
    'Ensures that no one can insert into this table directly, since the inserts
    should be ocurring at the order_item_<action>_<product> table';


-- function: order_prevent_if_short_id_exists()
-- description: prevent create if contact with short id already exists
CREATE OR REPLACE FUNCTION order_prevent_if_short_id_exists() RETURNS TRIGGER AS $$
BEGIN
    PERFORM TRUE
    FROM ONLY contact c
    WHERE c.short_id = NEW.short_id;

    IF FOUND THEN
        RAISE EXCEPTION 'contact already exists' USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;


-- function: validate_name_fqdn()
-- description: validates that order_host name is a valid FQDN
CREATE OR REPLACE FUNCTION validate_name_fqdn() RETURNS TRIGGER AS $$
BEGIN
    IF NOT ValidFQDN(NEW.name) THEN
        RAISE EXCEPTION 'Name % is not a valid FQDN', NEW.name;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: notify_order_status_transition_tgf()
-- description: Notify about an order status transition to a fixed channel
CREATE OR REPLACE FUNCTION notify_order_status_transition_tgf() RETURNS TRIGGER AS $$
DECLARE
    v_channel   TEXT;
BEGIN

    v_channel := 'notification_channel_order_status';

    PERFORM pg_notify(
            v_channel,
            JSONB_BUILD_OBJECT(
                    'order_id',OLD.id,
                    'status',tc_name_from_id('order_status',NEW.status_id))::TEXT
            );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: notify_order_status_transition_orderid_tgf()
-- description: Notify about an order status transition to a channel specific to a given order id
CREATE OR REPLACE FUNCTION notify_order_status_transition_orderid_tgf() RETURNS TRIGGER AS $$
DECLARE
    v_channel   TEXT;
BEGIN

    v_channel := FORMAT('notify_chnl_orderstatus_%s',REPLACE(OLD.id::TEXT,'-','_'));

    PERFORM pg_notify(
            v_channel,
            JSONB_BUILD_OBJECT(
                    'order_id',OLD.id,
                    'status',tc_name_from_id('order_status',NEW.status_id))::TEXT
            );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: notify_order_status_transition_final_tgf()
-- description: Notify about an order status transitioning to a final state to a channel specific to a given order id
CREATE OR REPLACE FUNCTION notify_order_status_transition_final_tfg() RETURNS TRIGGER AS $$
DECLARE
    _payload      JSONB;
BEGIN
    _payload = build_order_notification_payload(OLD.id);
    PERFORM notify_event('order_notify','order_event_notify',_payload::TEXT);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_set_metadata()
-- description: Update order metadata by adding order id;
CREATE OR REPLACE FUNCTION order_set_metadata() RETURNS TRIGGER AS $$
BEGIN
    NEW.metadata = COALESCE(NEW.metadata, '{}'::jsonb) || JSONB_BUILD_OBJECT ('order_id', NEW.id);
    RETURN NEW;
END
$$ LANGUAGE plpgsql;


-- function: order_item_set_tld_id()
-- description: this trigger function will set the NEW.accreditation_tld_id column
-- based on get_accreditation_tld_by_name(NEW.name, tenant_customer_id)
CREATE OR REPLACE FUNCTION order_item_set_tld_id() RETURNS TRIGGER AS  $$
DECLARE
    tc_id      UUID;
    v_acc_tld  RECORD;
BEGIN
    SELECT tenant_customer_id INTO tc_id FROM "order" WHERE id=NEW.order_id;
    v_acc_tld := get_accreditation_tld_by_name(NEW.name, tc_id);

    IF v_acc_tld IS NULL THEN
        RAISE EXCEPTION 'unsupported domain name ''%''', NEW.name;
    END IF;

    NEW.accreditation_tld_id = v_acc_tld.accreditation_tld_id;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;


-- function: order_item_set_idn_uname()
-- description: this trigger function will set the NEW.uname column
CREATE OR REPLACE FUNCTION order_item_set_idn_uname() RETURNS TRIGGER AS  $$
BEGIN
    -- if the uname is not set, we will set it to the name
    IF NEW.uname IS NULL THEN
        NEW.uname = NEW.name;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- function: order_process_items()
-- description: this is triggered when the order goes from new to pending
-- and is in charge of updating the items and setting status 'ready'
CREATE OR REPLACE FUNCTION order_process_items() RETURNS TRIGGER AS $$
BEGIN

    UPDATE order_item SET status_id = tc_id_from_name('order_item_status','ready')
    WHERE
        order_id=NEW.id
      AND status_id=tc_id_from_name('order_item_status','pending');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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


-- function: order_item_complete()
-- description: triggered when the order_item is complete
CREATE OR REPLACE FUNCTION order_item_finish() RETURNS TRIGGER AS $$
DECLARE
    v_oi_status RECORD;
BEGIN

    SELECT * INTO v_oi_status FROM order_item_status WHERE id=NEW.status_id;

    IF NOT v_oi_status.is_final THEN
        RETURN NEW;
    END IF;

    IF NEW.parent_order_item_id IS NULL THEN
        UPDATE "order"
        SET status_id=order_next_status(NEW.order_id,v_oi_status.is_success)
        WHERE id = NEW.order_id;
    ELSE
        -- TODO: How we can know which table the parent_order_item_id is referring to? Use rel_name from v_order_product_type or v_order_item_plan?
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: order_item_force_initial_status()
-- description: ensures that order_items start with pending
CREATE OR REPLACE FUNCTION order_item_force_initial_status() RETURNS TRIGGER AS $$
BEGIN

    NEW.status_id = tc_id_from_name('order_item_status','pending');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
