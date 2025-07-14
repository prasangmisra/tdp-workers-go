
--ARRAY['feedback', 'forum','cloud','hiphop','love','music','locker',	'click', 'country', 'diy', 'food', 'gift', 'juegos', 'lifestyle', 'link', 'living', 'property', 'sexy', 'vana'] 
-- tdp by dm_source and tld

SELECT 'tdp filter:dm_source,tld' AS name, (SELECT count(*) FROM only public.DOMAIN d  JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id  	WHERE vat.tenant_name=:dm_source_v   AND (:tld_v  IS NULL  OR vat.tld_name=ANY (:tld_v)) )  	AS d,
(SELECT count(*) FROM only public.contact c JOIN public.domain_contact dc ON dc.contact_id=c.id JOIN public.DOMAIN d ON d.id=dc.domain_id 	JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id WHERE vat.tenant_name=:dm_source_v   AND  tld_name= ANY(:tld_v) ) 	AS c,
(SELECT count(*) FROM public.contact_postal cp JOIN public.domain_contact dc ON dc.contact_id=cp.contact_id JOIN public.DOMAIN d ON d.id=dc.domain_id 	JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id WHERE vat.tenant_name=:dm_source_v   AND  tld_name= ANY(:tld_v)) AS cp,
(SELECT count(*) FROM public.domain_contact dc JOIN public.DOMAIN d ON d.id=dc.domain_id 	JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id 	WHERE vat.tenant_name=:dm_source_v   AND  tld_name= ANY(:tld_v))	AS dc,
(SELECT count(*) FROM public.domain_host dh JOIN public.DOMAIN d ON d.id=dh.domain_id JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id 	WHERE vat.tenant_name=:dm_source_v   AND  tld_name= ANY(:tld_v)) AS dh,
(SELECT count(*) FROM public.domain_lock dl JOIN public.DOMAIN d ON d.id=dl.domain_id JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id 	WHERE vat.tenant_name=:dm_source_v   AND  tld_name= ANY(:tld_v)) 	AS dl,
(SELECT count(*) FROM public.domain_rgp_status drs  JOIN public.DOMAIN d ON d.id=drs.domain_id JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id 	WHERE vat.tenant_name=:dm_source_v   AND  tld_name= ANY(:tld_v)) 	AS drs,
(SELECT count(*) FROM only public.order_item_import_domain od  JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=od.accreditation_tld_id  	WHERE vat.tenant_name=:dm_source_v   AND  tld_name= ANY(:tld_v))  	AS oid,
(SELECT count(*) FROM only public.ORDER o JOIN public.order_item_import_domain od ON od.order_id=o.id JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=od.accreditation_tld_id  	WHERE vat.tenant_name=:dm_source_v   AND  tld_name= ANY(:tld_v)) 	AS order;
 
-- tdp migrated by dm_source,tld
SELECT 'tdp migated filter:dm_source,tld' AS NAME,(SELECT count(*) FROM only public.DOMAIN d JOIN itdp.DOMAIN id ON id.id=d.id AND id.dm_source=:dm_source_v   AND  id.tld= ANY(:tld_v)) AS d,
(SELECT count(*) FROM only public.contact c JOIN itdp.contact ic ON ic.id=c.id  AND ic.dm_source=:dm_source_v   AND  ic.tld= ANY(:tld_v)  ) AS c,
(SELECT count(*) FROM public.contact_postal cp JOIN itdp.contact ic ON ic.id=cp.contact_id  AND ic.dm_source=:dm_source_v   AND  ic.tld= ANY(:tld_v) ) AS cp,
(SELECT count(*) FROM public.domain_contact  dc JOIN itdp.DOMAIN id ON id.id=dc.domain_id  AND id.dm_source=:dm_source_v   AND  id.tld= ANY(:tld_v)) AS dc,
(SELECT count(*) FROM only public.host h JOIN itdp.host ih ON ih.id=h.id  AND ih.dm_source=:dm_source_v   AND  ih.tld= ANY(:tld_v) )  AS h,
(SELECT count(*) FROM public.domain_host  dh JOIN itdp.DOMAIN id ON id.id=dh.domain_id  AND id.dm_source=:dm_source_v   AND  id.tld= ANY(:tld_v)) AS dh,
(SELECT count(*) FROM public.domain_lock  dh JOIN itdp.DOMAIN id ON id.id=dh.domain_id  AND id.dm_source=:dm_source_v   AND  id.tld= ANY(:tld_v)) AS dl,
(SELECT count(*) FROM public.domain_rgp_status  dh JOIN itdp.DOMAIN id ON id.id=dh.domain_id   AND id.dm_source=:dm_source_v   AND  id.tld= ANY(:tld_v))  AS drs,
(SELECT count(*) FROM only public.order_item_import_domain  dh JOIN itdp.DOMAIN id ON id.id=dh.domain_id  AND id.dm_source=:dm_source_v   AND  id.tld= ANY(:tld_v) ) AS oiid,
(SELECT count(*) FROM only public.ORDER o JOIN public.order_item_import_domain oiid ON oiid.order_id=o.id JOIN itdp.DOMAIN id ON id.id=oiid.domain_id  AND id.dm_source=:dm_source_v   AND  id.tld= ANY(:tld_v)) AS ORDER;


--itdp by dm_source,tld
SELECT  'itdp filter:dm_source,tld' AS NAME,  (SELECT count(*)   FROM  itdp."domain" WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v))  as d,
(SELECT count(*)   FROM  itdp.domain_error_records  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v)) as der,
(SELECT count(*)   FROM  itdp.domain_lock dl  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v) )  as dl,
(SELECT count(*)   FROM  itdp.contact  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v))  as c,
(SELECT count(*)   FROM  itdp.contact_error_records  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v))   as cer,
(SELECT count(*)   FROM  itdp.contact_postal  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v)) as cp,
(SELECT count(*)   FROM  itdp.contact_postal_error_records   WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v))   as cper,
(SELECT count(*)   FROM  itdp.host  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v)) as h_all,
(SELECT count(*)   FROM  itdp.host  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v) AND source_host_id IS NULL) as h_add,
(SELECT count(*)   FROM  itdp.host  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v) AND source_host_id IS not NULL) as h_clean,
(SELECT count(*)   FROM  itdp.host_error_records  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v))  as her_all,
(SELECT count(*)   FROM  itdp.host_error_records  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v)AND source_host_id IS NULL)  as her_add,
(SELECT count(*)   FROM  itdp.host_error_records  WHERE dm_source=:dm_source_v   AND  tld= ANY(:tld_v)AND source_host_id IS not NULL)  as her_clean;

--dm_enom by tld
SELECT  'dm_enom by tld' AS NAME, (SELECT count(*)   FROM  dm_enom.domainname_ WHERE   tld= ANY(:tld_v))  as d_,
(SELECT count(*)   FROM  dm_enom.domainname WHERE   tld= ANY(:tld_v))  as d,
(SELECT count(*)   FROM  dm_enom.domaincontact_ dc JOIN  dm_enom.domainname_ dn ON dn.domainnameid=dc.domainnameid  WHERE   tld= ANY(:tld_v) ) as dc_,
(SELECT count(*)   FROM  dm_enom.domaincontact dc JOIN  dm_enom.domainname_ dn ON dn.domainnameid=dc.domainnameid  WHERE   tld= ANY(:tld_v) ) as dc,
(SELECT count(*)   FROM  dm_enom.nameservers_ ns JOIN  dm_enom.domainname_ dn ON dn.domainnameid=ns.domainnameid  WHERE   tld= ANY(:tld_v)  )  as h_,
(SELECT count(*)   FROM  dm_enom.nameservers ns  WHERE   tld= ANY(:tld_v)  )  as h,
(SELECT count(*)   FROM  dm_enom.contact_ WHERE   tld= ANY(:tld_v))  as c_,
(SELECT count(*)   FROM  dm_enom.contact_private WHERE   tld= ANY(:tld_v) )  as cprivate,
(SELECT count(*)   FROM  dm_enom.contact WHERE   tld= ANY(:tld_v))  as c;







-------------------------------------------- TDP settings
SELECT tld_name,tenant_name,
get_tld_setting(p_key => 'tld.dns.allowed_nameserver_count',	p_tld_id=>vat.tld_id,    p_tenant_id=>vat.tenant_id)	AS range_nameservers,
get_tld_setting(p_key => 'tld.lifecycle.transfer_grace_period',	p_tld_id=>vat.tld_id,    p_tenant_id=>vat.tenant_id)	AS transfer_grace_period,
get_tld_setting(p_key => 'tld.lifecycle.redemption_grace_period',	p_tld_id=>vat.tld_id,    p_tenant_id=>vat.tenant_id)	AS redemption_grace_period,
get_tld_setting(p_key => 'tld.lifecycle.add_grace_period',	p_tld_id=>vat.tld_id,    p_tenant_id=>vat.tenant_id)	AS add_grace_period
FROM public.v_accreditation_tld vat
WHERE vat.tenant_name ='enom'
and tld_name in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu');

-----------------------
--Check domains with RGP status which not exists in public.domain_RGP_status table
SELECT d.name, d.deleted_date, * FROM public.DOMAIN d
JOIN itdp.DOMAIN id ON id.id=d.id
LEFT JOIN  public.domain_rgp_status drs on drs.domain_id=d.id
WHERE tc_name_from_id('itdp.domain_status',id.status_id)= 'RGP'
AND  drs.domain_id IS  NULL 
	;




--domain ------------------------------------------------------------------------
--compare  domain data
SELECT    roid, SLDdotTLD,authinfo,COALESCE(uname,SLDdotTLD) AS uname, expdate  ,  creationdate
,CASE WHEN CAST(transferindate AS date) <'2022-01-15' THEN     (transferindate  + interval '7 hour') 
     WHEN CAST(transferindate AS date)>='2022-01-15' THEN (transferindate  + interval '6 hour')
    END     as transferindate,
CASE WHEN CAST(deldate AS date) <'2022-01-15' THEN     (deldate  + interval '7 hour') 
     WHEN CAST(deldate AS date)>='2022-01-15' THEN     (deldate  + interval '6 hour') 
    END     as deldate
FROM dm_enom.domainname WHERE  itdp_domain_id IS NOT NULL  AND tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')

-- AND SLDdotTLD='wealthclub.link'
EXCEPT
SELECT  roid, "name", auth_info,uname, ry_expiry_date AT time zone 'UTC', ry_created_date AT time zone 'UTC' 
,ry_transfered_date AT time zone 'UTC',  deleted_date AT time zone 'UTC'
FROM  only public.domain 
WHERE substring(name,POSITION ('.' IN name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;
--where name='wealthclub.link' ;



--compare  domain data
SELECT  roid, "name", auth_info,uname,ry_expiry_date AT time zone 'UTC', ry_created_date AT time zone 'UTC' 
,ry_transfered_date AT time zone 'UTC',  deleted_date AT time zone 'UTC'
FROM only public.domain 
WHERE substring(name,POSITION ('.' IN name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	
EXCEPT
SELECT     roid, SLDdotTLD,authinfo, COALESCE(uname,SLDdotTLD),expdate  ,  creationdate 
,CASE WHEN CAST(transferindate AS date) <'2022-01-15' THEN     (transferindate  + interval '7 hour') 
     WHEN CAST(transferindate AS date)>='2022-01-15' THEN (transferindate  + interval '6 hour')
    END     as transferindate,
CASE WHEN CAST(deldate AS date) <'2022-01-15' THEN     (deldate  + interval '7 hour') 
     WHEN CAST(deldate AS date)>='2022-01-15' THEN     (deldate  + interval '6 hour') 
    END     as deldate
FROM dm_enom.domainname WHERE  itdp_domain_id IS NOT NULL  AND tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;


--------------host--------------------------------------------------------------------------------
--compare  migrated  host data
SELECT n.name,d.SLDdotTLD
FROM dm_enom.nameservers n
JOIN dm_enom.domainname d ON d.domainnameid=n.domainnameid
WHERE   itdp_host_id IS NOT NULL   AND n.tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')	
EXCEPT 
SELECT h.name,d.name FROM  only public.host h
JOIN only public.domain_host dh ON dh.host_id =h.id
JOIN only public.domain d ON dh.domain_id=d.id
WHERE substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
;


SELECT n.name,d.name
FROM itdp.host n
JOIN itdp.domain d ON d.id=n.itdp_domain_id
WHERE  n.tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')	
EXCEPT 
SELECT h.name,d.name FROM  only public.host h
JOIN only public.domain_host dh ON dh.host_id =h.id
JOIN only public.domain d ON dh.domain_id=d.id
WHERE substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;

--compare  migrated  host data
SELECT h.name,d.name FROM  only public.host h
JOIN only public.domain_host dh ON dh.host_id =h.id
JOIN only public.domain d ON dh.domain_id=d.id
WHERE substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	
EXCEPT
SELECT n.name,d.name
FROM itdp.host n
JOIN itdp.domain d ON d.id=n.itdp_domain_id
WHERE  n.tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
;

--compare  migrated  host data 
;WITH dns AS 
( SELECT 'dns1.name-services.com' AS name
UNION ALL 
SELECT 'dns2.name-services.com' AS name
UNION ALL 
 SELECT 'dns3.name-services.com' AS name
UNION ALL 
 SELECT 'dns4.name-services.com' AS name
UNION ALL 
 SELECT 'dns5.name-services.com' AS name)	
 
(SELECT n.name,d.SLDdotTLD  
	FROM dm_enom.nameservers n
	JOIN dm_enom.domainname d ON d.domainnameid=n.domainnameid
	WHERE   itdp_host_id IS NOT NULL   AND n.tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')

UNION ALL 
SELECT  dns.name ,d.slddottld  
	FROM dm_enom.domainname d
	CROSS JOIN dns
	WHERE d.tld  in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	  AND d.itdp_domain_id IS NOT NULL AND
	d.NSStatus = 'Yes' AND NOT EXISTS (SELECT 1 FROM dm_enom.nameservers h1 where h1.tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	 and h1.domainnameid=d.domainnameid))
EXCEPT 
SELECT h.name,d.name FROM only public.host h --650
	JOIN only public.domain_host dh ON dh.host_id =h.id
	JOIN only public.domain d ON dh.domain_id=d.id
	WHERE substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;

---------------------------------------------------------
--compare  migrated  host data
;WITH dns AS 
( SELECT 'dns1.name-services.com' AS name
UNION ALL 
SELECT 'dns2.name-services.com' AS name
UNION ALL 
 SELECT 'dns3.name-services.com' AS name
UNION ALL 
 SELECT 'dns4.name-services.com' AS name
UNION ALL 
 SELECT 'dns5.name-services.com' AS name)	 

SELECT h.name::varchar(255)as host_name,trim(d.name) as domain_name 
FROM only public.host h
	JOIN only public.domain_host dh ON dh.host_id =h.id
	JOIN only public.domain d ON dh.domain_id=d.id
	WHERE substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	
EXCEPT 
(SELECT n.name::varchar(255) as host_name,trim(d.SLDdotTLD)  as domain_name
	FROM dm_enom.nameservers n
	JOIN dm_enom.domainname d ON d.domainnameid=n.domainnameid
	WHERE   itdp_host_id IS NOT NULL   AND n.tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	
UNION ALL 
SELECT  dns.name::varchar(255)  ,d.slddottld 
	FROM dm_enom.domainname d
	CROSS JOIN dns
	WHERE d.tld  in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
 	 AND 	d.itdp_domain_id IS NOT NULL AND
	d.NSStatus = 'Yes' AND NOT EXISTS (SELECT 1 FROM dm_enom.nameservers h1 where h1.tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	 and h1.domainnameid=d.domainnameid)
);


------contact------------------------------------
--compare migrated contact data
SELECT itdp_contact_id,lower(email_address),
phone_number,fax_number,country_code
,first_name, last_name,organization,   address1,address2, address3, city,postal_code, state
FROM dm_enom.contact WHERE itdp_contact_id IS NOT NULL  AND tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')	
EXCEPT 
SELECT c.id,c.email, 
c.phone ,c.fax, c.country
,first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
FROM only public.contact c
JOIN only public.contact_postal cp ON cp.contact_id=c.id
JOIN only public.domain_contact dc ON dc.contact_id=c.id
JOIN only public.domain d ON dc.domain_id=d.id
JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id
WHERE  tenant_name='enom'  AND substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;



--compare migrated contact data
SELECT c.id, c.email, c.phone ,c.fax, c.country
,first_name, last_name, org_name, address1, address2, address3, city, postal_code, state
FROM only public.contact c
JOIN only public.contact_postal cp ON cp.contact_id=c.id
JOIN only public.domain_contact dc ON dc.contact_id=c.id
JOIN only public.domain d ON dc.domain_id=d.id
join public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id
WHERE  tenant_name='enom' AND substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')

EXCEPT 
SELECT itdp_contact_id,lower(email_address),
phone_number,fax_number,country_code
,first_name, last_name,organization,   address1,address2, address3, city,postal_code, state
FROM dm_enom.contact 
WHERE tld in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
		AND  itdp_contact_id IS NOT null;

--- country_code
select 'tdp' as schema_name,country,c.id as contact_id,d.name as domain_name ,'' as c_type from public.contact c
JOIN only public.domain_contact dc ON dc.contact_id=c.id
JOIN only public.domain d ON dc.domain_id=d.id
where c.id='7a564739-6641-4dc8-967d-c5161d865db7'
/*union all 
select 'itdp' as schema_name,country,c.id as contact_id,d.name as domain_name,'' as c_type
from itdp.contact c
JOIN itdp.domain d ON c.itdp_domain_id=d.id
where c.id='7a564739-6641-4dc8-967d-c5161d865db7'*/
union all
select 'dm_enom' as schema_name,country_code as counry ,c.itdp_contact_id as contact_id,d.slddottld as domain_name ,c_type
from dm_enom.contact c 
join dm_enom.domainname d on d.domainnameid=c.domainnameid
where itdp_contact_id='7a564739-6641-4dc8-967d-c5161d865db7'



--- data issue ----------------------------------------------------------------------------------------------

--min_nameservers
/*SELECT * FROM public.domain
WHERE  (metadata->'migration_info'->>'min_nameservers_issue') :: boolean */

SELECT name, migration_info,* FROM only public.domain d
WHERE  (migration_info->>'allowed_nameserver_count_issue') = 'true'
and substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
;


-- contact issues
-- country
SELECT edc.country_code,country, * 
from only public.contact c
JOIN only public.domain_contact dc ON dc.contact_id=c.id
JOIN only public.domain d ON dc.domain_id=d.id
LEFT JOIN dm_enom.contact edc ON edc.itdp_contact_id=c.id
WHERE c.migration_info->>'data_source' = 'Enom' 
	AND jsonb_typeof(c.migration_info->'invalid_fields') != 'null'
	AND   substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;



-- handle
SELECT * FROM only public.contact c
JOIN only public.domain_contact dc ON dc.contact_id=c.id
JOIN only public.domain d ON dc.domain_id=d.id
WHERE c.migration_info->>'lost_handle' = 'true'
AND   substring(d.name,POSITION ('.' IN d.name)+1,20) in  ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;

--city issue
SELECT d.name,* FROM public.contact_postal cp
JOIN only public.contact c ON c.id=cp.contact_id
JOIN public.domain_contact dc ON dc.contact_id=c.id
JOIN public.domain d ON dc.domain_id=d.id
WHERE C.migration_info->>'data_source' = 'Enom' AND (city ='Unknown City' OR city='')
AND   substring(d.name,POSITION ('.' IN d.name)+1,20) in ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;

--address1 issue
SELECT d.name,* FROM public.contact_postal cp
JOIN only public.contact c ON c.id=cp.contact_id
JOIN public.domain_contact dc ON dc.contact_id=c.id
JOIN public.domain d ON dc.domain_id=d.id
WHERE c.migration_info->>'data_source' = 'Enom' AND (address1  ='Unknown Address1' OR address1='')
AND   substring(d.name,POSITION ('.' IN d.name)+1,20) in ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;


-- public contact  data was replaced on placeholder contact data  
SELECT d.name, c.migration_info,ct.name,c.* FROM only public.contact c
join public.contact_type ct on ct.id=c.type_id
JOIN public.domain_contact dc ON dc.contact_id=c.id
JOIN public.domain d ON dc.domain_id=d.id
WHERE c.migration_info->>'placeholder' = 'true'
AND   substring(d.name,POSITION ('.' IN d.name)+1,20) in ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	;

SELECT d.name, count(*) FROM only public.contact c
join public.contact_type ct on ct.id=c.type_id
JOIN public.domain_contact dc ON dc.contact_id=c.id
JOIN public.domain d ON dc.domain_id=d.id
WHERE c.migration_info->>'placeholder' = 'true'
AND   substring(d.name,POSITION ('.' IN d.name)+1,20) in ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	
group by  d.name;





-----------post migration script for create report -------------------------------------------------------------------------


--domain
select id.tld,d.name,d.auto_renew, d.roid,  d.auth_info,d.uname, d.ry_expiry_date  as ry_expiry_date,
d.ry_created_date  as ry_created_date
,d.ry_transfered_date  as ry_transfered_date,  d.deleted_date  as deleted_date, migration_info,
case when dl.type_id is not null then tc_name_from_id('public.lock_type',dl.type_id) end as lock,is_internal as is_internal_lock,
case when dr.status_id is not null then tc_name_from_id('public.rgp_status',dr.status_id) end   as rgp_status,dr.expiry_date as rgp_status_expiry_date
FROM public.domain d 
join itdp.domain id on id.id=d.id
left join public.domain_lock dl on dl.domain_id=d.id
left join public.domain_rgp_status dr on dr.domain_id=d.id 
WHERE substring(d.name,POSITION ('.' IN d.name)+1,20) in ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	 order by 1,2;
--and d.name in ('alpha.rest','enom-test-dec9-3.bar')


-- host
SELECT substring(d.name,POSITION ('.' IN d.name)+1,20) as tld,d.name as domain_name, h.name as host_name  FROM only public.host h --650
	JOIN only public.domain_host dh ON dh.host_id =h.id
	JOIN only public.domain d ON dh.domain_id=d.id
	join itdp.domain id on id.id=d.id
	WHERE substring(d.name,POSITION ('.' IN d.name)+1,20)in ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	 order by 1,2,3;
	
--contact
SELECT substring(d.name,POSITION ('.' IN d.name)+1,20) as tld,d.name as domain_name,dct.name as contact_type,c.id,c.email, 
c.phone ,c.fax, c.country
,first_name, last_name, org_name, address1, address2, address3, city, postal_code, state, c.migration_info
FROM only public.contact c
JOIN only public.contact_postal cp ON cp.contact_id=c.id
JOIN only public.domain_contact dc ON dc.contact_id=c.id
JOIN only public.domain d ON dc.domain_id=d.id
join public.domain_contact_type dct on dct.id=domain_contact_type_id
JOIN  itdp.domain id ON id.id=d.id and id.tld in ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	 and dm_source='enom'
JOIN public.v_accreditation_tld vat ON vat.accreditation_tld_id=d.accreditation_tld_id
WHERE  tenant_name='enom'  AND substring(d.name,POSITION ('.' IN d.name)+1,20)  in ('shop','nagoya','tokyo','yokohama','okinawa','ryukyu')
	 order by 1,2,3;






