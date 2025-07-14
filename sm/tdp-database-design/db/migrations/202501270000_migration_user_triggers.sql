CREATE OR REPLACE FUNCTION public.is_data_migration() RETURNS BOOLEAN AS $$
  SELECT (current_user = 'migration_user');
$$ LANGUAGE SQL  IMMUTABLE;

DROP TRIGGER IF EXISTS domain_rgp_status_set_expiration_tg ON public.domain_rgp_status;
CREATE TRIGGER domain_rgp_status_set_expiration_tg 
    BEFORE INSERT ON public.domain_rgp_status   
    FOR EACH ROW  WHEN (NOT is_data_migration() ) EXECUTE PROCEDURE domain_rgp_status_set_expiry_date();
   
DROP TRIGGER  IF EXISTS  order_set_metadata_tg  ON public."order"  ; 
CREATE TRIGGER order_set_metadata_tg 
  AFTER INSERT ON "order" 
  FOR EACH ROW  WHEN (NOT is_data_migration() ) EXECUTE PROCEDURE order_set_metadata(); 
 
 \i triggers.ddl