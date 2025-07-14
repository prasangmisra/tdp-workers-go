
INSERT INTO error_category ( name, descr )
VALUES
  ( 'fv', 'field validation' ),
  ( 'ic', 'integrity constraints' ),
  ( 'sc', 'security controls' )
;

WITH cat AS (
    SELECT *
    FROM error_category
    WHERE name = 'fv'
)
INSERT INTO error_dictionary( category_id, id, message, columns_affected )
SELECT cat.id, v.column1, v.column2, v.column3
FROM cat
     JOIN (
       VALUES
         ( 1000, 'unknown country id passed', '{"country"}'::TEXT[] )
       , ( 1001, 'country selection requires state/province', '{"country"}'::TEXT[] )
       , ( 1002, 'invalid country/sp combination', '{"country","state/province"}'::TEXT[] )
      ) v ON TRUE
;

WITH cat AS (
    SELECT *
    FROM error_category
    WHERE name = 'sc'
)
INSERT INTO error_dictionary( category_id, id, message, columns_affected )
SELECT cat.id, v.column1, v.column2, v.column3
FROM cat
     JOIN (
       VALUES
         ( 3000, 'invalid password', '{"password"}'::TEXT[] )
      ) v ON TRUE
;
