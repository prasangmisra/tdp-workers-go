DROP TRIGGER IF EXISTS order_prevent_if_renew_unsupported_tg ON order_item_renew_domain;

DROP TRIGGER IF EXISTS order_prevent_if_delete_unsupported_tg ON order_item_delete_domain;

DROP FUNCTION IF EXISTS order_prevent_if_delete_unsupported();

DROP FUNCTION IF EXISTS order_prevent_if_renew_unsupported();

DELETE FROM attr_key
       WHERE name = 'explicit_delete_supported' OR
             name = 'explicit_renew_supported';
