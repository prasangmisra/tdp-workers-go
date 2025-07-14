
CREATE OR REPLACE FUNCTION lookup_error ( _id INT )
RETURNS JSONB AS
$$
DECLARE
    v_error_r RECORD;
BEGIN

    SELECT * INTO v_error_r FROM v_error_dictionary WHERE id = _id;

    IF NOT FOUND THEN
       RETURN json_build_object( 'id', -1
                               , 'category', NULL
                               , 'message'
                               , format( 'message not defined in dictionary: %s', _id )
                               );
    END IF;

    RETURN to_json(v_error_r)::jsonb;

END;
$$
LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION lookup_error ( INT ) IS '

Lookup the given message id in the L<error_dictionary> table,
returning a template exception string.

If the passed message id is not found, a default error message is
composed and returned to the caller, with no interpolation.

';

CREATE OR REPLACE FUNCTION lookup_error ( _id INT, _parms TEXT[] )
RETURNS JSONB AS
$$
DECLARE
    v_msg     JSONB;
BEGIN

    v_msg   := lookup_error ( _id );
    RETURN v_msg || json_build_object( 'fields', _parms )::jsonb;

END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION lookup_error ( INT, TEXT[] ) IS '

Lookup the given message id in the L<error_dictionary> table,
returning a properly composed JSONB string to be used in a C<RAISE
EXCEPTION> elsewhere in the code. This includes interpolation of
additional parameters passed in as a C<TEXT[] ARRAY>.

If the passed message id is not found, a default error message is
composed and returned to the caller, with no interpolation.

';
