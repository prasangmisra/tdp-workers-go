--
-- function: get_data_elements
-- description: This function retrieves data elements based on provided parameters.
--
CREATE OR REPLACE FUNCTION get_domain_data_elements_for_permission(
    p_tld_id UUID DEFAULT NULL,
    p_tld_name TEXT DEFAULT NULL,
    p_data_element_parent_id UUID DEFAULT NULL,
    p_data_element_parent_name TEXT DEFAULT NULL,
    p_permission_id UUID DEFAULT NULL,
    p_permission_name TEXT DEFAULT NULL
) 
RETURNS TEXT[] AS $$
DECLARE
    data_elements TEXT[];
BEGIN
    IF p_tld_id IS NULL AND p_tld_name IS NULL THEN
        RAISE EXCEPTION 'Either p_tld_id or p_tld_name must be provided';
    END IF;

    IF p_data_element_parent_id IS NULL AND p_data_element_parent_name IS NULL THEN
        RAISE EXCEPTION 'Either p_data_element_parent_id or p_data_element_parent_name must be provided';
    END IF;

    IF p_permission_id IS NULL AND p_permission_name IS NULL THEN
        RAISE EXCEPTION 'Either p_permission_id or p_permission_name must be provided';
    END IF;

    SELECT ARRAY_AGG(vddep.data_element_name)
    INTO data_elements
    FROM v_domain_data_element_permission vddep
    WHERE (vddep.permission_name = p_permission_name OR vddep.permission_id = p_permission_id)
      AND (vddep.tld_id = p_tld_id OR vddep.tld_name = p_tld_name)
      AND (vddep.data_element_parent_id = p_data_element_parent_id OR vddep.data_element_parent_name = p_data_element_parent_name)
      AND (
        vddep.validity IS NULL
        OR (
            UPPER(vddep.validity) > CURRENT_TIMESTAMP
            AND
            LOWER(vddep.validity) <= CURRENT_TIMESTAMP
        )
    );
   
    RETURN data_elements;
END;
$$ LANGUAGE plpgsql;
