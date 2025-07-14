INSERT INTO supported_protocol(name,descr) VALUES('epp','Extensible Provisioning Protocol');


INSERT into tld_type (name, descr) VALUES
   ('country_code', 'ccTLD'),
   ('generic', 'gTLD');


INSERT INTO rgp_status (name, epp_name, descr) VALUES
   ('add_grace_period', 'addPeriod', 'registry provides credit for deleted domain during this period for the cost of the registration'),
   ('transfer_grace_period', 'transferPeriod', 'registry provides credit for deleted domain during this period for the cost of the transfer'),
   ('autorenew_grace_period', 'autoRenewPeriod', 'registry provides credit for deleted domain during this period for the cost of the renewal'),
   ('redemption_grace_period', 'redemptionPeriod', 'deleted domain might be restored during this period'),
   ('pending_delete_period', 'pendingDelete', 'deleted domain not restored during redemptionPeriod');
