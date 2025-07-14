
DROP TABLE IF EXISTS dm_enom.map_domain_status_enom_itdp ;

CREATE  TABLE IF NOT EXISTS  dm_enom.map_domain_status_enom_itdp (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
	itdp_id uuid NOT NULL ,
	itdp_name text NOT NULL,
	enom_name text NULL,	
	CONSTRAINT domain_status_name_key UNIQUE (itdp_name,enom_name),
	CONSTRAINT domain_status_pkey PRIMARY KEY (id)
);

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

ALTER TABLE  IF EXISTS  dm_enom.contact_ ADD IF NOT EXISTS  inserteddate timestampz;