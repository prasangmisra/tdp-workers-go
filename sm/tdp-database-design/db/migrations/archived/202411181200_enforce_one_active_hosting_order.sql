CREATE OR REPLACE VIEW v_hosting_order_item AS

SELECT
    oich.id AS order_item_id,
    oich.order_id,
    oich.domain_name,
    os.is_final AS order_status_is_final
FROM
  order_item_create_hosting oich
    JOIN "order" o ON o.id = oich.order_id
    JOIN order_status os ON os.id = o.status_id

UNION ALL

SELECT
  oiuh.id AS order_item_id,
  oiuh.order_id,
  h.domain_name,
  os.is_final AS order_status_is_final
FROM
  order_item_update_hosting oiuh
    JOIN "order" o ON o.id = oiuh.order_id
    JOIN order_status os ON os.id = o.status_id
    JOIN hosting h on h.id = oiuh.hosting_id

UNION ALL

SELECT
  oidh.id AS order_item_id,
  oidh.order_id,
  h.domain_name,
  os.is_final AS order_status_is_final
FROM 
  order_item_delete_hosting oidh
    JOIN "order" o ON o.id = oidh.order_id
    JOIN order_status os ON os.id = o.status_id
    JOIN hosting h on h.id = oidh.hosting_id
;

CREATE OR REPLACE FUNCTION enforce_single_active_hosting_order_by_name() RETURNS TRIGGER AS $$
BEGIN
    PERFORM 1 FROM v_hosting_order_item WHERE domain_name = NEW.domain_name AND NOT order_status_is_final LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Active order for Hosting ''%'' currently exists', NEW.domain_name USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;

END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_single_active_hosting_order_by_id() RETURNS TRIGGER AS $$
DECLARE
    hosting_name TEXT;
BEGIN
    SELECT domain_name FROM hosting WHERE id = NEW.hosting_id INTO hosting_name;

    PERFORM 1 FROM v_hosting_order_item WHERE domain_name = hosting_name AND NOT order_status_is_final LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Active order for Hosting ''%'' currently exists', hosting_name USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS order_item_check_active_orders_tg ON order_item_create_hosting;
DROP TRIGGER IF EXISTS order_item_check_active_orders_tg ON order_item_delete_hosting;
DROP TRIGGER IF EXISTS order_item_check_active_orders_tg ON order_item_update_hosting;

CREATE TRIGGER order_item_check_active_orders_tg
    BEFORE INSERT ON order_item_update_hosting
    FOR EACH ROW EXECUTE PROCEDURE enforce_single_active_hosting_order_by_id();

CREATE TRIGGER order_item_check_active_orders_tg
    BEFORE INSERT ON order_item_delete_hosting
    FOR EACH ROW EXECUTE PROCEDURE enforce_single_active_hosting_order_by_id();

CREATE TRIGGER order_item_check_active_orders_tg
  BEFORE INSERT ON order_item_create_hosting
  FOR EACH ROW EXECUTE PROCEDURE enforce_single_active_hosting_order_by_name();