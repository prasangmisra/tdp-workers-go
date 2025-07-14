-- Products
INSERT INTO product (name) VALUES ('domain'),('certificate'),('contact'),('hosting'),('host');

-- Order Types
INSERT INTO order_type (product_id,name) SELECT id, 'create' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'transfer_in' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'transfer_away' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'update' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'changeholder' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'renew' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'redeem' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'expire' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'unexpire' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'delete' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'transit' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'import' FROM product WHERE name = 'domain';

INSERT INTO order_type (product_id,name) SELECT id, 'new' FROM product WHERE name = 'certificate';
INSERT INTO order_type (product_id,name) SELECT id, 'reissue' FROM product WHERE name = 'certificate';
INSERT INTO order_type (product_id,name) SELECT id, 'renew' FROM product WHERE name = 'certificate';

INSERT INTO order_type (product_id,name) SELECT id, 'create' FROM product WHERE name = 'contact';
INSERT INTO order_type (product_id,name) SELECT id, 'update' FROM product WHERE name = 'contact';
INSERT INTO order_type (product_id,name) SELECT id, 'delete' FROM product WHERE name = 'contact';

INSERT INTO order_type (product_id, name) SELECT id, 'create' FROM product WHERE name = 'hosting';
INSERT INTO order_type (product_id, name) SELECT id, 'update' FROM product WHERE name = 'hosting';
INSERT INTO order_type (product_id, name) SELECT id, 'delete' FROM product WHERE name = 'hosting';

INSERT INTO order_type (product_id,name) SELECT id, 'create' FROM product WHERE name = 'host';
INSERT INTO order_type (product_id,name) SELECT id, 'update' FROM product WHERE name = 'host';
INSERT INTO order_type (product_id,name) SELECT id, 'delete' FROM product WHERE name = 'host';

INSERT INTO order_type (product_id,name) SELECT id, 'create_internal' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'update_internal' FROM product WHERE name = 'domain';
INSERT INTO order_type (product_id,name) SELECT id, 'delete_internal' FROM product WHERE name = 'domain';

-- Order Statuses
INSERT INTO order_status (name,descr,is_final,is_success) 
  VALUES
  ('created','Newly created order', FALSE, TRUE),
  ('processing','Processing is underway', FALSE, TRUE),
  ('failed','The order failed', TRUE, FALSE),
  ('successful','The order was completed successfully',TRUE,TRUE);

INSERT INTO order_item_status(name,descr,is_final,is_success) 
  VALUES
  ('pending','Pending for order to be ready',FALSE,FALSE),
  ('ready','Ready to be processed',FALSE,FALSE),
  ('canceled','Canceled',TRUE,FALSE),
  ('complete','Complete',TRUE,TRUE);


  INSERT INTO order_status_path(name,descr)
  VALUES
  ('default','Default order path');


INSERT INTO order_status_transition(path_id,from_id,to_id)
  (
    WITH transitions AS (
      SELECT * FROM (
        VALUES
        ('created','processing'),
        ('created','failed'),
        ('processing','successful'),
        ('processing','failed')
        ) AS t (from_status,to_status)
    )
    SELECT tc_id_from_name('order_status_path','default'),s.id,t.id
      FROM transitions
        JOIN order_status s ON s.name = transitions.from_status
        JOIN order_status t ON t.name = transitions.to_status
  );

INSERT INTO order_item_plan_status(name,descr,is_success,is_final)
  VALUES
    ('new','processing has not started',TRUE,FALSE),
    ('processing','processing started, waiting completion',TRUE,FALSE),
    ('completed','completed satisfactory',TRUE,TRUE),
    ('failed','job processing failed',FALSE,TRUE);

INSERT INTO order_item_plan_validation_status(name,descr,is_success,is_final)
  VALUES
    ('pending','validation pending, waiting start',TRUE,FALSE),
    ('started','validation started, waiting completion',TRUE,FALSE),
    ('completed','validation succeeded',TRUE,TRUE),
    ('failed','validation failed',FALSE,TRUE);


INSERT INTO order_item_object(name,descr)
  VALUES
    ('domain','domain object'),
    ('host','host object'),
    ('contact','contact_object'),
    ('hosting', 'hosting object'),
    ('hosting_certificate', 'hosting certificate object');


INSERT INTO order_item_strategy(order_type_id, object_id, is_validation_required, provision_order)
  VALUES
    (
      (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='create'),
      tc_id_from_name('order_item_object','host'),
      TRUE,
      1
    ),
    (
      (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='create'),
      tc_id_from_name('order_item_object','contact'),
      FALSE,
      1
    ),
    (
      (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='create'),
      tc_id_from_name('order_item_object','domain'),
      TRUE,
      2
    ),
    (
      (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='renew'),
      tc_id_from_name('order_item_object','domain'),
      TRUE,
      1
    ),
    (
      (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='redeem'),
      tc_id_from_name('order_item_object','domain'),
      TRUE,
      1
    ),
    (
      (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='delete'),
      tc_id_from_name('order_item_object','domain'),
      FALSE,
      1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update'),
        tc_id_from_name('order_item_object','host'),
        TRUE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update'),
        tc_id_from_name('order_item_object','contact'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update'),
        tc_id_from_name('order_item_object','domain'),
        TRUE,
        2
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_in'),
        tc_id_from_name('order_item_object','domain'),
        TRUE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_in'),
        tc_id_from_name('order_item_object','domain'),
        FALSE,
        2
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_away'),
        tc_id_from_name('order_item_object','domain'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='transfer_away'),
        tc_id_from_name('order_item_object','domain'),
        FALSE,
        2
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='contact' AND type_name='create'),
        tc_id_from_name('order_item_object','contact'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='contact' AND type_name='delete'),
        tc_id_from_name('order_item_object','contact'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='hosting' AND type_name='create'),
        tc_id_from_name('order_item_object','hosting_certificate'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='hosting' AND type_name='create'),
        tc_id_from_name('order_item_object','hosting'),
        FALSE,
        2
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='hosting' AND type_name='delete'),
        tc_id_from_name('order_item_object','hosting'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='hosting' AND type_name='update'),
        tc_id_from_name('order_item_object','hosting'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='host' AND type_name='create'),
        tc_id_from_name('order_item_object','host'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='contact' AND type_name='update'),
        tc_id_from_name('order_item_object','contact'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='host' AND type_name='update'),
        tc_id_from_name('order_item_object','host'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='host' AND type_name='delete'),
        tc_id_from_name('order_item_object','host'),
        FALSE,
        1
    ),
    (
        (SELECT type_id FROM v_order_product_type WHERE product_name='domain' AND type_name='update_internal'),
        tc_id_from_name('order_item_object','domain'),
        FALSE,
        1
    )
    ;

-- Transfer Statuses
INSERT INTO transfer_status (name,descr,is_final,is_success) 
  VALUES
  ('pending','Newly created transfer request', FALSE, FALSE),
  ('clientApproved','Approved by loosing registrar', TRUE, TRUE),
  ('clientRejected','Rejected by loosing registrar',TRUE, FALSE),
  ('clientCancelled','Cancelled by gaining registrar', TRUE, FALSE),
  ('serverApproved','Approved by registry', TRUE, TRUE),
  ('serverCancelled','Cancelled by registry', TRUE, FALSE);
