DROP TRIGGER IF EXISTS validate_idn_lang_tg ON order_item_create_domain;

DROP FUNCTION IF EXISTS validate_idn_lang();
