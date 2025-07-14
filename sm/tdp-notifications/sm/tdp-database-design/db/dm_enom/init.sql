INSERT INTO dm_enom.map_country_enom_itdp(name, alpha2, enom_alpha2)
	VALUES
		('United Kingdom of Great Britain and Northern Ireland', 'GB', 'UK'),
		('Equatorial Guinea', 'GQ', 'EK')
ON CONFLICT DO NOTHING ;

INSERT INTO dm_enom.map_domain_status_enom_itdp (itdp_id,itdp_name,enom_name) 
    VALUES        
        ('24ac43cb-ff01-459a-8ed7-d1846b0404aa','Deleted','Deleted'),
	    ('c0928677-ca0b-49fd-9df7-43446f9889cc','RGP','Imminent Delete'),
	    ('24ac43cb-ff01-459a-8ed7-d1846b0404aa','Deleted','Transferred away'),
	    ('24ac43cb-ff01-459a-8ed7-d1846b0404aa','Deleted', 'Expired Transfers'),
	    ('ddfa2bed-e332-40b9-9244-2440ffa2d555','Active', 'Registered'),
		('ad4432b5-b99c-4385-ac33-477e6446216f','Expired', 'Expired'),      
		('b6131b33-1f4e-4169-93d7-6795009c3e7e','Extended RGP','Extended RGP'),
		('c0928677-ca0b-49fd-9df7-43446f9889cc','RGP','RGP'),
		('c0928677-ca0b-49fd-9df7-43446f9889cc','RGP','RGP Deactivated')
ON CONFLICT DO NOTHING ;

INSERT INTO dm_enom.map_lock_type_enom_itdp (itdp_id,itdp_name, enom_name)
	VALUES  
		 ('3d97d496-4f1d-11e8-9bfd-02420a000396','hold', 'Hold') ,
		 ('8261baeb-89fc-4020-9e05-b17158f11d9c','transfer','CustomerDomainStatus')
ON CONFLICT DO NOTHING ;