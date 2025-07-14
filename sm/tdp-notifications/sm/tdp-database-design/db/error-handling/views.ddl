
DROP VIEW IF EXISTS v_error_dictionary CASCADE;
CREATE OR REPLACE VIEW v_error_dictionary AS

SELECT
  d.id          AS id,
  c.name        AS category,
  d.message     AS message,
  d.columns_affected AS columns_affected
FROM error_dictionary d
  JOIN error_category c ON c.id=d.category_id
;
