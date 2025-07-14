
CREATE OR REPLACE FUNCTION trg_right_enforce_order() RETURNS TRIGGER AS
$$
BEGIN

  PERFORM TRUE
  FROM right_order ro
  WHERE NOT ro.block_matching
        AND ro.deleted_by IS NULL
        AND ( ro.tenant_customer_id IS NULL
              OR ro.tenant_customer_id = NEW.tenant_customer_id )
        AND ( ro.order_type_id IS NULL
              OR ro.order_type_id = NEW.order_type_id )
        AND ( ro.tenant_id IS NULL
              OR ( EXISTS ( SELECT TRUE
                            FROM tenant_customer tc
                                 JOIN tenant t
                                      ON tc.tenant_id = t.id
                                         AND tc.id = NEW.tenant_customer_id
                                         AND t.id = ro.tenant_id )))
        AND ( ro.customer_id IS NULL
              OR ( EXISTS ( SELECT TRUE
                            FROM tenant_customer tc
                                 JOIN customer c
                                      ON tc.customer_id = c.id
                                         AND tc.id = NEW.tenant_customer_id
                                         AND c.id = ro.customer_id )))
        AND ( ro.product_id IS NULL
              OR ( EXISTS ( SELECT TRUE
                            FROM order_type ot
                                 JOIN product p
                                      ON ot.id = NEW.order_type_id
                                         AND ot.product_id = p.id
                                         AND ro.product_id = p.id )))
  ;

  IF FOUND THEN
    RETURN NEW;
  END IF;

  PERFORM TRUE
  FROM right_order ro
  WHERE ro.block_matching
        AND ro.deleted_by IS NULL
        AND ( ro.tenant_customer_id IS NULL
              OR ro.tenant_customer_id = NEW.tenant_customer_id )
        AND ( ro.order_type_id IS NULL
              OR ro.order_type_id = NEW.order_type_id )
        AND ( ro.tenant_id IS NULL
              OR ( EXISTS ( SELECT TRUE
                            FROM tenant_customer tc
                                 JOIN tenant t
                                      ON tc.tenant_id = t.id
                                         AND tc.id = NEW.tenant_customer_id
                                         AND t.id = ro.tenant_id )))
        AND ( ro.customer_id IS NULL
              OR ( EXISTS ( SELECT TRUE
                            FROM tenant_customer tc
                                 JOIN customer c
                                      ON tc.customer_id = c.id
                                         AND tc.id = NEW.tenant_customer_id
                                         AND c.id = ro.customer_id )))
        AND ( ro.product_id IS NULL
              OR ( EXISTS ( SELECT TRUE
                            FROM order_type ot
                                 JOIN product p
                                      ON ot.id = NEW.order_type_id
                                         AND ot.product_id = p.id
                                         AND ro.product_id = p.id )))
  ;

  IF FOUND THEN
    RAISE EXCEPTION 'operation blocked by right constraint';
  END IF;

  RETURN NEW;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER
;
