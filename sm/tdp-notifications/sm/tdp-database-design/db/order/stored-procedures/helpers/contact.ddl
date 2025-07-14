-- function: check_contact_field_changed_in_order_contact()
-- description: checks if one of the passed fields in contact has changed in order contact
CREATE OR REPLACE FUNCTION check_contact_field_changed_in_order_contact(_oc_id UUID, _c_id UUID, _fields TEXT[]) RETURNS BOOLEAN AS $$
DECLARE
    _jsn_oc     JSON;
    _jsn_c      JSON;
    _c          TEXT;
BEGIN
    SELECT jsonb_get_order_contact_by_id(_oc_id)
    INTO _jsn_oc;

    SELECT jsonb_get_contact_by_id(_c_id)
    INTO _jsn_c;

    FOREACH _c IN ARRAY _fields
        LOOP
            -- check contact
            IF _jsn_oc->>_c IS DISTINCT FROM _jsn_c->>_c THEN
                RETURN TRUE;
            END IF;

            -- check contact postals
            PERFORM TRUE FROM json_array_elements((_jsn_oc->>'contact_postals')::JSON) AS ocp
                                  JOIN json_array_elements((_jsn_c->>'contact_postals')::JSON) AS cp
                                       ON cp->>'is_international' = ocp->>'is_international'
            WHERE ocp->>_c IS DISTINCT FROM cp->>_c;
            IF FOUND THEN
                RETURN TRUE;
            END IF;
        END LOOP;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;
