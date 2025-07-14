CREATE UNIQUE INDEX ON order_item_create_domain(name,accreditation_tld_id) 
  WHERE status_id = tc_id_from_name('order_item_status','pending') 
    OR status_id = tc_id_from_name('order_item_status','ready');

CREATE UNIQUE INDEX ON order_item_redeem_domain(name,accreditation_tld_id) 
  WHERE status_id = tc_id_from_name('order_item_status','pending') 
    OR status_id = tc_id_from_name('order_item_status','ready');    

CREATE UNIQUE INDEX ON order_item_renew_domain(name,accreditation_tld_id) 
  WHERE status_id = tc_id_from_name('order_item_status','pending') 
    OR status_id = tc_id_from_name('order_item_status','ready');  

CREATE UNIQUE INDEX ON order_item_delete_domain(name,accreditation_tld_id) 
  WHERE status_id = tc_id_from_name('order_item_status','pending') 
    OR status_id = tc_id_from_name('order_item_status','ready'); 

CREATE UNIQUE INDEX ON order_item_transfer_in_domain(name,accreditation_tld_id)
  WHERE status_id = tc_id_from_name('order_item_status','pending') 
    OR status_id = tc_id_from_name('order_item_status','ready'); 

CREATE UNIQUE INDEX ON order_item_transfer_away_domain(name,accreditation_tld_id)
  WHERE status_id = tc_id_from_name('order_item_status','pending')
    OR status_id = tc_id_from_name('order_item_status','ready');

CREATE UNIQUE INDEX ON order_item_update_domain(name,accreditation_tld_id)
  WHERE status_id = tc_id_from_name('order_item_status','pending')
    OR status_id = tc_id_from_name('order_item_status','ready');
