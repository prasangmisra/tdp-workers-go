CREATE UNIQUE INDEX ON provision_domain(domain_name)
  WHERE 
       status_id = tc_id_from_name('provision_status','pending')
    OR status_id = tc_id_from_name('provision_status','processing')
    OR status_id = tc_id_from_name('provision_status','completed')
  ;
