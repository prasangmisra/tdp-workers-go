--cleaning tdpdb.public for repeating migration--------------------------------------------------
---for repeat  ------------------------------------------------------------------------------------------------
-- MIGRATION_USER !!!!!

DO LANGUAGE plpgsql  $$	
DECLARE dm_source_v varchar :='enom' ; 	
DECLARE   tld_v varchar[] := ARRAY['shop','nagoya','tokyo','yokohama','okinawa','ryukyu'] ; 
BEGIN
	 DELETE FROM public.domain_contact dc
	 USING  public.DOMAIN d
	 JOIN itdp.DOMAIN id ON id.id=d.id and dm_source=dm_source_v and  id.tld = ANY(tld_v)
	 WHERE d.id=dc.domain_id ;
	
	 DELETE FROM public.domain_host dh
	 USING  public.DOMAIN d
	 JOIN itdp.DOMAIN id ON id.id=d.id  and id.dm_source=dm_source_v and   id.tld = ANY(tld_v)
	 WHERE d.id=dh.domain_id ;
COMMIT;
END $$;
              -----------------------------------
DO LANGUAGE plpgsql  $$	
DECLARE dm_source_v varchar :='enom' ; 	
DECLARE   tld_v varchar[] := ARRAY['shop','nagoya','tokyo','yokohama','okinawa','ryukyu']  ; 
BEGIN 
	 DELETE FROM  only public.host h
	 USING itdp.host ih
	 WHERE ih.id=h.id AND ih.dm_source=dm_source_v  AND   ih.tld = ANY(tld_v)
	 AND NOT EXISTS (SELECT 1 FROM public.domain_host dh where dh.host_id=h.id); 
	
	 DELETE  FROM  public.domain_rgp_status drs
	 USING  public.DOMAIN d
	 JOIN itdp.DOMAIN id ON id.id=d.id and id.dm_source=dm_source_v and   id.tld = ANY(tld_v)
	 WHERE d.id=drs.domain_id;
	
	 DELETE  FROM  public.domain_lock dl
	 USING  public.DOMAIN d
	 JOIN itdp.DOMAIN id ON id.id=d.id and id.dm_source=dm_source_v and   id.tld = ANY(tld_v)
	 WHERE d.id=dl.domain_id ;
COMMIT;
END $$;
             -------------------------------------
DO LANGUAGE plpgsql  $$	
DECLARE dm_source_v varchar :='enom' ; 	
DECLARE   tld_v varchar[] :=ARRAY['shop','nagoya','tokyo','yokohama','okinawa','ryukyu']  ; 
BEGIN 
	WITH CTE AS 
	(	SELECT oiid.* FROM order_item_import_domain oiid
		JOIN itdp.DOMAIN id ON oiid.id=id.id and id.dm_source=dm_source_v and   id.tld = ANY(tld_v)		
	),		
	CTE_O AS 
	(	DELETE  FROM  only public.ORDER o     
		USING  CTE
		WHERE CTE.order_id=o.id
	)
	DELETE  FROM  only public.order_item_import_domain oiid     
	USING  CTE
	WHERE CTE.id=oiid.id;
	
	DELETE  FROM  public.DOMAIN d     
	USING  itdp.DOMAIN id
	WHERE id.id=d.id and id.dm_source=dm_source_v and   id.tld = ANY(tld_v)	;	

COMMIT;
END $$;

DO LANGUAGE plpgsql  $$	
DECLARE dm_source_v varchar :='enom' ; 	
DECLARE   tld_v varchar[] := ARRAY['shop','nagoya','tokyo','yokohama','okinawa','ryukyu']  ; 
BEGIN 
	ALTER TABLE public.contact_postal DISABLE TRIGGER zz_50_sofdel_contact_postal;	
	DELETE from public.contact_postal cp
	USING only public.contact c  
	JOIN itdp.contact ic ON ic.id=c.id and ic.dm_source=dm_source_v and   ic.tld = ANY(tld_v)	
	WHERE cp.contact_id=c.id ;
	ALTER TABLE public.contact_postal ENABLE TRIGGER zz_50_sofdel_contact_postal;
COMMIT;
END $$;

DO LANGUAGE plpgsql  $$	
DECLARE dm_source_v varchar :='enom' ; 	
DECLARE   tld_v varchar[] := ARRAY['shop','nagoya','tokyo','yokohama','okinawa','ryukyu'] ; 
BEGIN 
	ALTER TABLE public.contact DISABLE TRIGGER zz_50_sofdel_contact;
	DELETE from  only public.contact c  
	USING itdp.contact ic
	WHERE ic.id=c.id and ic.dm_source=dm_source_v and   ic.tld = ANY(tld_v)	;
	ALTER TABLE public.contact ENABLE  TRIGGER zz_50_sofdel_contact;

	UPDATE itdp.DOMAIN SET dm_status=NULL  WHERE     tld = ANY(tld_v);

COMMIT;
END $$;




-----------------------------------------------------------------------------

--Clean ITDP -----------------------
/*
DO LANGUAGE plpgsql  $$	
DECLARE dm_source_v varchar :='enom' ; 	
DECLARE   tld_v varchar[] := ARRAY['shop','nagoya','tokyo','yokohama','okinawa','ryukyu'] ; 
BEGIN 
		DELETE FROM  itdp.domain_error_records     WHERE  dm_source=dm_source_v and    tld = ANY(tld_v);
		DELETE FROM  itdp.domain_lock dl  USING  itdp.DOMAIN id WHERE id.id=dl.domain_id AND id.dm_source=dm_source_v   AND   id.tld = ANY(tld_v);
		DELETE FROM  itdp.host    WHERE dm_source=dm_source_v   AND   tld = ANY(tld_v);
		DELETE FROM  itdp.host_error_records     WHERE dm_source=dm_source_v   AND    tld = ANY(tld_v);
		DELETE FROM  itdp.contact_postal    WHERE dm_source=dm_source_v   AND  tld = ANY(tld_v);
		DELETE FROM  itdp.contact_postal_error_records     WHERE dm_source=dm_source_v   AND   tld = ANY(tld_v);
		DELETE FROM  itdp.contact    WHERE dm_source=dm_source_v   AND   tld = ANY(tld_v);
		DELETE FROM  itdp.contact_error_records     WHERE dm_source=dm_source_v   AND   tld = ANY(tld_v);
		DELETE FROM  itdp."domain"    WHERE  dm_source=dm_source_v   AND  tld = ANY(tld_v);
		--DELETE FROM  itdp.dm_log    WHERE dm_source=dm_source_v   AND  tld_v  IS NULL ;
		
		UPDATE dm_enom.domainname SET  itdp_domain_id=NULL   WHERE  tld = ANY(tld_v);
		UPDATE dm_enom.nameservers ns SET  itdp_host_id=NULL, itdp_domain_id=NULL  
		FROM dm_enom.nameservers nss 
		WHERE ns.idx=nss.idx  AND ns.tld = ANY(tld_v);
		
		UPDATE dm_enom.contact SET  itdp_contact_id=NULL WHERE    tld = ANY(tld_v);
		UPDATE itdp.tld SET  migration_status=null, result_domain=null,result_contact=null,result_host=null, updated_date=null 
		WHERE    tld_name = ANY(tld_v);


--- Clean dm_enom ------------------------

DELETE  FROM  dm_enom.domaincontact_ dc USING  dm_enom.domainname_ dn WHERE  dn.domainnameid=dc.domainnameid AND  tld = ANY(tld_v);
DELETE  FROM  dm_enom.nameservers_   ns USING dm_enom.domainname_ dn WHERE dn.domainnameid=ns.domainnameid  AND  tld = ANY(tld_v);
DELETE  FROM  dm_enom.domainname_ WHERE  tld = ANY(tld_v);
--DELETE  FROM  dm_enom.contact_ WHERE  tld = ANY(tld_v);
DELETE  FROM  dm_enom.contact_private WHERE  tld = ANY(tld_v);
DELETE  FROM  dm_enom.domaincontact  dc USING dm_enom.domainname dn WHERE dn.domainnameid=dc.domainnameid  AND  tld = ANY(tld_v);
DELETE  FROM  dm_enom.nameservers  ns WHERE  tld = ANY(tld_v);
DELETE  FROM  dm_enom.contact WHERE  tld = ANY(tld_v);
DELETE  FROM   dm_enom.domainname WHERE  tld = ANY(tld_v);

COMMIT;
END $$;
*/
-- all tdp
SELECT 'all tdp' AS name,(SELECT count(*) FROM only public.DOMAIN) AS d,
(SELECT count(*) FROM only public.contact) AS c,
(SELECT count(*) FROM public.contact_postal) AS cp,
(SELECT count(*) FROM public.domain_contact) AS dc,
(SELECT count(*) FROM only public.host) AS h,
(SELECT count(*) FROM public.domain_host) AS dh,
(SELECT count(*) FROM public.domain_lock) AS dl,
(SELECT count(*) FROM public.domain_rgp_status ) AS drs,
(SELECT count(*) FROM only public.order_item_import_domain ) AS oiid,
(SELECT count(*) FROM only public.ORDER o JOIN public.order_item_import_domain oiid ON oiid.order_id=o.id) AS ORDER;

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

-- all dm_enom
SELECT   'dm_enom all' AS NAME, (SELECT count(*)   FROM  dm_enom.domainname_ )  as d__all,
(SELECT count(*)   FROM  dm_enom.domainname )  as d_all,
(SELECT count(*)   FROM  dm_enom.domaincontact_ dc ) as dc__all,
(SELECT count(*)   FROM  dm_enom.domaincontact dc  ) as dc_all,
(SELECT count(*)   FROM  dm_enom.nameservers_ ns  )  as ns__all,
(SELECT count(*)   FROM  dm_enom.nameservers ns  )  as ns_all,
(SELECT count(*)   FROM  dm_enom.contact_ )  as c__all,
(SELECT count(*)   FROM  dm_enom.contact_private  )  as cprivate_all,
(SELECT count(*)   FROM  dm_enom.contact )  as c_all;