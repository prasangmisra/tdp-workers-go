
DROP TRIGGER IF EXISTS v_attribute_update_tg ON v_attribute;
CREATE TRIGGER v_attribute_update_tg INSTEAD OF UPDATE ON v_attribute 
    FOR EACH ROW EXECUTE PROCEDURE attribute_update();
