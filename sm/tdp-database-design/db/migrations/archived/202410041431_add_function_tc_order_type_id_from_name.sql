-- tc_order_type_id_from_name(order_type TEXT, product TEXT)
--       This function returns the order_type_id for a given order_type and product
--
CREATE OR REPLACE FUNCTION tc_order_type_id_from_name(order_type TEXT, product TEXT) RETURNS UUID AS $$
DECLARE
    _result UUID;
BEGIN

    EXECUTE 'SELECT ot.id FROM order_type ot INNER JOIN product p ON ot.product_id = p.id WHERE ot.name = $1 AND p.name = $2' INTO STRICT _result
        USING order_type, product;
    RETURN _result;

END;
$$ LANGUAGE plpgsql IMMUTABLE;