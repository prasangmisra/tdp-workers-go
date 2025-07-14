-- migration user creation and grants for local DB
DO $$BEGIN
IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'migration_user')
THEN CREATE USER  migration_user  WITH PASSWORD 'tucows1234';
END IF;
END$$;

GRANT  USAGE ON SCHEMA itdp TO migration_user ;
GRANT  CREATE  ON SCHEMA itdp TO migration_user ;
GRANT  USAGE ON SCHEMA dm_enom TO migration_user ;
GRANT  CREATE  ON SCHEMA dm_enom TO migration_user ;
GRANT  USAGE ON SCHEMA public TO migration_user ;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO migration_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA itdp TO migration_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA dm_enom TO migration_user;

ALTER TABLE ITDP.DOMAIN OWNER TO  migration_user;
ALTER TABLE ITDP.host OWNER TO  migration_user;
ALTER TABLE ITDP.contact OWNER TO  migration_user;
ALTER TABLE ITDP.contact_postal OWNER TO  migration_user;

-- data to be used for testing purposes

INSERT INTO business_entity(name,descr) 
    VALUES
        ('tucows','Tucows Inc.'),
        ('unr','UNR Corp.'),
        ('xyz','XYZ.COM LLC'),
        ('centralnic','CentralNIC PLC'),
        ('squarespace','Sparespace');

INSERT INTO tenant(id,business_entity_id,name,descr)
    VALUES
    ('26ac88c7-b774-4f56-938b-9f7378cb3eca', tc_id_from_name('business_entity','tucows'),'opensrs','OpenSRS Registrar'),
    ('dc9cb205-e858-4421-bf2c-6e5ebe90991e', tc_id_from_name('business_entity','tucows'),'enom','eNom Registrar'),
    ('ba79a7e5-352f-4078-af0d-01a7a84cb8aa', tc_id_from_name('business_entity','tucows'),'ascio','Ascio Registrar');

INSERT INTO customer(business_entity_id,name,descr)
    VALUES(tc_id_from_name('business_entity','squarespace'),'squarespace-reseller','Squarespace.com');


INSERT INTO tenant_customer(id, tenant_id,customer_id,customer_number)
    VALUES
    -- seeding specific tenant_customer_id which is used in testing hosting flows as resellerId on AWS account
        ('d50ff47e-2a80-4528-b455-6dc5d200ecbe', tc_id_from_name('tenant','opensrs'),tc_id_from_name('customer','squarespace-reseller'),'1234567' ),
    -- seeding random tenant_customer_id which is used in testing domain flows from Enom bridge
        ('9fb3982f-1e77-427b-b5ed-e76f676edbd4', tc_id_from_name('tenant','enom'),tc_id_from_name('customer','squarespace-reseller'),'1234567' ),
    -- seeding random tenant_customer_id which is used in testing domain flows from Ascio
        ('078b93b4-8d2f-4a34-82d1-36d568bbb042', tc_id_from_name('tenant','ascio'),tc_id_from_name('customer','squarespace-reseller'),'1234567' );

INSERT INTO "user"(email,name)
    VALUES
        ('user1@squarespace.com','Jane Roe Squarespace'),
        ('user2@squarespace.com','John Doe Squarespace');

INSERT INTO customer_user(customer_id,user_id)
    VALUES
        (tc_id_from_name('customer','squarespace-reseller'),tc_id_from_name('"user"','John Doe Squarespace')),
        (tc_id_from_name('customer','squarespace-reseller'),tc_id_from_name('"user"','Jane Roe Squarespace'));

INSERT INTO registry(business_entity_id,name,descr)
    VALUES
        (tc_id_from_name('business_entity','unr'),'unr-registry','UNR Registry'),
        (tc_id_from_name('business_entity','xyz'),'xyz-registry','XYZ Registry');

INSERT INTO tld(name,registry_id, type_id)
    VALUES
        ('bar', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('claims', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('help', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('sexy', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('country', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('blackfriday', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('christmas', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('click', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('diet', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('flowers', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('game', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('gift', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('guitars', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('hiphop', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('hiv', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('hosting', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('juegos', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('link', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('lol',	tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('photo', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('pics', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('property', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('tattoo', tc_id_from_name('registry','unr-registry'), tc_id_from_name('tld_type','generic')),
        ('xyz', tc_id_from_name('registry','xyz-registry'), tc_id_from_name('tld_type','generic')),
        ('auto', tc_id_from_name('registry','xyz-registry'), tc_id_from_name('tld_type','generic'));

INSERT INTO provider (business_entity_id,name,descr) 
    VALUES 
        (tc_id_from_name('business_entity','tucows'),'trs','Tucows Registry Services'),
        (tc_id_from_name('business_entity','centralnic'),'centralnic-registry','CentralNIC Registry Services');


INSERT INTO provider_protocol(provider_id,supported_protocol_id)
    (SELECT bp.id,p.id FROM provider bp,supported_protocol p );

INSERT INTO provider_instance(provider_id,name,descr,is_proxy)
    VALUES
    (tc_id_from_name('provider','trs'),'trs-uniregistry','Uniregistry Instance',FALSE),
    (tc_id_from_name('provider','trs'),'trs-bar-instance','TRS Bar Instance',FALSE),
    (tc_id_from_name('provider','centralnic-registry'),'centralnic-default','Default Instance',FALSE);

INSERT INTO provider_instance_tld(provider_instance_id,tld_id)
    VALUES
        (tc_id_from_name('provider_instance','trs-bar-instance'),tc_id_from_name('tld','bar')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','claims')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','help')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','sexy')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','country')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','blackfriday')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','christmas')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','click')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','diet')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','flowers')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','game')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','gift')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','guitars')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','hiphop')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','hiv')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','hosting')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','juegos')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','link')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','lol')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','photo')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','pics')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','property')),
        (tc_id_from_name('provider_instance','trs-uniregistry'),tc_id_from_name('tld','tattoo')),
        (tc_id_from_name('provider_instance','centralnic-default'),tc_id_from_name('tld','xyz')),
        (tc_id_from_name('provider_instance','centralnic-default'),tc_id_from_name('tld','auto'));


INSERT INTO provider_instance_epp(provider_instance_id,host)
    VALUES
        (tc_id_from_name('provider_instance','trs-uniregistry'),'epp.uniregistry.net'),
        (tc_id_from_name('provider_instance','centralnic-default'),'epp.centralnic.com');


INSERT INTO accreditation(tenant_id,provider_instance_id,registrar_id,name)
    VALUES
        (tc_id_from_name('tenant','opensrs'),tc_id_from_name('provider_instance','trs-uniregistry'),'tucows_a','opensrs-uniregistry'),
        (tc_id_from_name('tenant','enom'),tc_id_from_name('provider_instance','trs-uniregistry'),'tucows_b','enom-uniregistry'),
        (tc_id_from_name('tenant','enom'),tc_id_from_name('provider_instance','trs-bar-instance'),'enom','enom-trs-bar'),
        (tc_id_from_name('tenant','opensrs'),tc_id_from_name('provider_instance','centralnic-default'),'tucows','opensrs-centralnic'),
        (tc_id_from_name('tenant','enom'),tc_id_from_name('provider_instance','centralnic-default'),'enom','enom-centralnic');


INSERT INTO accreditation_epp(accreditation_id,clid,pw)
    VALUES
    (tc_id_from_name('accreditation','opensrs-uniregistry'),'tucows','tucows1234'),
    (tc_id_from_name('accreditation','enom-uniregistry'),'enom','enom1234'),
    (tc_id_from_name('accreditation','enom-trs-bar'),'enom_a','enom_a12471'),
    (tc_id_from_name('accreditation','opensrs-centralnic'),'tucows','tucows-cnic-1234'),
    (tc_id_from_name('accreditation','enom-centralnic'),'enom','enom-cnic-1234');


INSERT INTO accreditation_tld(accreditation_id,provider_instance_tld_id)
    (SELECT a.id,t.id 
        FROM accreditation a 
            JOIN provider_instance_tld t ON a.provider_instance_id = t.provider_instance_id);


INSERT INTO domain(
tenant_customer_id,
accreditation_tld_id,
name,
ry_created_date,
ry_expiry_date,
expiry_date
) VALUES(
    (SELECT id FROM tenant_customer LIMIT 1),
    (SELECT accreditation_tld_id FROM v_accreditation_tld WHERE tld_name='sexy' LIMIT 1),
    'example-to-be-renewed.sexy',
    NOW(),
    NOW() + '1 year'::INTERVAL,
    NOW() + '1 year'::INTERVAL
),
(
    (SELECT id FROM tenant_customer LIMIT 1),
    (SELECT accreditation_tld_id FROM v_accreditation_tld WHERE tld_name='sexy' LIMIT 1),
    'example-to-be-deleted.sexy',
    NOW(),
    NOW() + '1 year'::INTERVAL,
    NOW() + '1 year'::INTERVAL
)
;



INSERT INTO attribute(type_id,name,descr,parent_id) 
    VALUES
        (tc_id_from_name('attribute_type','contact'),'xxx','XXX requirements',NULL);

INSERT INTO attribute(type_id,name,descr,parent_id) 
    VALUES
        (tc_id_from_name('attribute_type','contact'),'membership_id','Membership Number',tc_id_from_name('attribute','xxx'));

-- finance settings test 
INSERT INTO finance_setting (type_id, tenant_id, value_text_list, validity)
VALUES
    (tc_id_from_name('finance_setting_type', 'tenant.accepts_currencies'), tc_id_from_name('tenant','opensrs'), ARRAY['USD','DKK','EUR','SGD'], tstzrange(NULL, NULL)), 
    (tc_id_from_name('finance_setting_type', 'tenant.accepts_currencies'), tc_id_from_name('tenant','ascio'), ARRAY['USD','EUR'], tstzrange(NULL, NULL));

-- seed sample data element permissions
WITH tld_id AS (
    SELECT tc_id_from_name('tld', 'click') AS id
),
registrant_email_tld AS (
    INSERT INTO domain_data_element (data_element_id, tld_id) VALUES (
        (SELECT id FROM v_data_element WHERE full_name = 'registrant.email'),
        (SELECT id FROM tld_id)
    ) RETURNING id
),
registrant_first_name_tld AS (
    INSERT INTO domain_data_element (data_element_id, tld_id) VALUES (
        (SELECT id FROM v_data_element WHERE full_name = 'registrant.first_name'),
        (SELECT id FROM tld_id)
    ) RETURNING id
),
registrant_last_name_tld AS (
    INSERT INTO domain_data_element (data_element_id, tld_id) VALUES (
        (SELECT id FROM v_data_element WHERE full_name = 'registrant.last_name'),
        (SELECT id FROM tld_id)
    ) RETURNING id
)
INSERT INTO domain_data_element_permission (domain_data_element_id, permission_id)
VALUES
    (
        (SELECT id FROM registrant_email_tld),
        tc_id_from_name('permission', 'may_collect')
    ),
    (
        (SELECT id FROM registrant_email_tld),
        tc_id_from_name('permission', 'must_collect')
    ),
    (
        (SELECT id FROM registrant_first_name_tld),
        tc_id_from_name('permission', 'must_collect')
    ),
    (
        (SELECT id FROM registrant_last_name_tld),
        tc_id_from_name('permission', 'must_not_collect')
    ),
    (
        (SELECT id FROM registrant_email_tld),
        tc_id_from_name('permission', 'transmit_to_registry')
    ),
    (
        (SELECT id FROM registrant_first_name_tld),
        tc_id_from_name('permission', 'transmit_to_escrow')
    ),
    (
        (SELECT id FROM registrant_email_tld),
        tc_id_from_name('permission', 'available_for_consent')
    ),
    (
        (SELECT id FROM registrant_first_name_tld),
        tc_id_from_name('permission', 'publish_by_default')
    );
