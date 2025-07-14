/*INSERT INTO dm_opensrs.map_domain_status_enom_itdp (itdp_id,itdp_name,enom_name) 
    VALUES     
('ddfa2bed-e332-40b9-9244-2440ffa2d555','Active', 'Active'),
('c0928677-ca0b-49fd-9df7-43446f9889cc','RGP','RGP')		
ON CONFLICT DO NOTHING ;

INSERT INTO dm_opensrs.map_lock_type_enom_itdp (itdp_id,itdp_name, enom_name)
	VALUES  
		 ('3d97d496-4f1d-11e8-9bfd-02420a000396','hold', 'lock_hold') ,
		 ('8261baeb-89fc-4020-9e05-b17158f11d9c','transfer','lock_transfer'),
		 ('ff4231ac-51d6-11e8-8b70-02420a000525','delete','lock_delete'),
		 ('0a510fb2-0c6d-11ea-901c-0242ac11001b','update','lock_update')
ON CONFLICT DO NOTHING ;*/