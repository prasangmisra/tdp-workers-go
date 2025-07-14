
-- 1. filter out only relevant domains in dm_ascio.domain_filtered
INSERT INTO dm_ascio.domain_filtered  
    SELECT  *  
    FROM dm_ascio.all_domains
    WHERE domain_status not in ('Pending', 'Deleted');

-- dm_ascio.domain_filtered 
WITH del AS (
    SELECT * 
    FROM dm_ascio.deleted_domains_rgp 
    )
    INSERT INTO dm_ascio.domain_filtered 
        SELECT  s.* 
        FROM dm_ascio.all_domains s
        JOIN del 
            ON s.domain_name = del.domain
        WHERE domain_status ='Deleted'; 

-- 2. dm_ascio SCHEMA
-- dm_ascio.domain
INSERT INTO dm_ascio.domain ( 
	"name",  
	auth_info, 
	roid, 
	ry_created_date, 
	ry_expiry_date,
	ry_updated_date,
	ry_transfered_date,
	deleted_date,
	expiry_date,
	secdns_max_sig_life,
	idn_uname,
	idn_lang,
	source_Ascio_domain_id,
	source_Ascio_reseller_id
    )
    SELECT 
        domain_name, 
        domain_authorization,
        NULL,
        CAST(domain_created AS TIMESTAMP) AT TIME ZONE 'UTC',
        CAST(domain_expires AS TIMESTAMP) AT TIME ZONE 'UTC',
        CAST(domain_updated AS TIMESTAMP) AT TIME ZONE 'UTC',
        NULL,
        CASE WHEN domain_status != 'Deleted' THEN NULL
            ELSE CAST(domain_deleted AS TIMESTAMP) AT TIME ZONE 'UTC'
            END CASE,
        CAST(domain_expires AS TIMESTAMP) AT TIME ZONE 'UTC',
        NULL, 
        CASE WHEN name like '%.in' 
            THEN NULL
            ELSE name 
        END uname,
        NULL, 
        domain_handle,
        domain_owner
    FROM dm_ascio.domain_filtered;  

-- dm_ascio.domain_lock
WITH split_statuses AS (  
    SELECT 
        d.source_domain_id AS domain_id,
        f.domain_name,
        unnest(string_to_array(f.domain_status, ', ')) AS status -- Split and expand statuses
    FROM dm_ascio.domain_filtered f
    JOIN dm_ascio.domain d 
        ON d."name" = f.domain_name
    )
    INSERT INTO dm_ascio.domain_lock (
        domain_id,
        lock
    )
    SELECT 
        domain_id,
        CASE 
            WHEN status = 'Delete_Lock' THEN 'delete_lock'
            WHEN status = 'Transfer_Lock' THEN 'transfer_lock'
            WHEN status = 'Update_Lock' THEN 'update_lock'
        END AS lock
    FROM split_statuses
    WHERE status IN ('Delete_Lock', 'Transfer_Lock', 'Update_Lock');

-- dm_ascio.domain_rgp_status
INSERT INTO dm_ascio.domain_rgp_status(
	domain_id, status, created_date, expiry_date
    )
    SELECT d.source_domain_id, domain_status, 
        CAST(domain_deleted AS TIMESTAMP) AT TIME ZONE 'UTC', 
        (domain_deleted::TIMESTAMPTZ AT TIME ZONE 'UTC') + INTERVAL '720 hours'
    FROM dm_ascio.domain_filtered f
    JOIN dm_ascio.domain d ON d.name = f.domain_name 
    WHERE domain_status ='Deleted'; 

-- dm_ascio.host, dm_ascio,host_addr, dm_ascio.domain_host
CREATE TEMP TABLE host_temp 
	(domain_uuid text
	, source_domain_id int 
	,domain_name text
	,ns_hostname TEXT
	,domain_ns_handle text	
	,ns_ipaddress text); 

INSERT INTO host_temp
	(domain_uuid , source_domain_id, domain_name, ns_hostname, domain_ns_handle, ns_ipaddress)
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns1_hostname, f.domain_ns1_handle, ns1_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns1_hostname IS NOT null and f.ns1_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns2_hostname, f.domain_ns2_handle, ns2_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns2_hostname IS NOT null and f.ns2_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns3_hostname, f.domain_ns3_handle, ns3_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns3_hostname IS NOT null and f.ns3_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns4_hostname, f.domain_ns4_handle, ns4_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns4_hostname IS NOT null and f.ns4_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns5_hostname, f.domain_ns5_handle, ns5_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns5_hostname IS NOT null and f.ns5_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns6_hostname, f.domain_ns6_handle, ns6_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns6_hostname IS NOT null and f.ns6_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns7_hostname, f.domain_ns7_handle, ns7_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns7_hostname IS NOT null and f.ns7_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns8_hostname, f.domain_ns8_handle, ns8_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns8_hostname IS NOT null and f.ns8_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns9_hostname, f.domain_ns9_handle, ns9_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns9_hostname IS NOT null and f.ns8_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns10_hostname, f.domain_ns10_handle, ns10_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns10_hostname IS NOT null and f.ns10_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns11_hostname, f.domain_ns11_handle, ns11_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns11_hostname IS NOT null and f.ns11_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns12_hostname, f.domain_ns12_handle, ns12_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns12_hostname IS NOT null and f.ns12_hostname <> ''
	UNION all
	select d.id AS domain_uuid, d.source_domain_id, d.name,  f.ns13_hostname, f.domain_ns13_handle, ns13_ipaddress
	from dm_ascio.domain_filtered f
	join dm_ascio.domain d on d.name = f.domain_name
	WHERE f.ns13_hostname IS NOT null and f.ns13_hostname <> '' ;

INSERT INTO dm_ascio.host 
	("name", domain_id, domain_ns_handle)
	SELECT 
		ns_hostname, source_domain_id, domain_ns_handle 
	FROM host_temp; 

-- remove duplicates - bug from PROD ASCIO
WITH cte_duplicates AS (
    SELECT 
        id,
        ROW_NUMBER() OVER (PARTITION BY name, domain_id ORDER BY id) AS row_num
    FROM dm_ascio.host
    )
    DELETE FROM dm_ascio.host
    WHERE id IN (
        SELECT id
        FROM cte_duplicates
        WHERE row_num > 1
    );

INSERT INTO dm_ascio.host_addr
	(host_id, address)
	SELECT DISTINCT  h.source_host_id, ht.ns_ipaddress::inet
	FROM host_temp ht
	JOIN dm_ascio.host h ON  ht.ns_hostname = h.name 
	WHERE ns1_ipaddress <> ''; 

-- remove duplicated 
WITH cte_duplicates AS (
    SELECT 
        id,
        ROW_NUMBER() OVER (PARTITION BY host_id, address ORDER BY id) AS row_num
    FROM dm_ascio.host_addr
    )
    DELETE FROM dm_ascio.host_addr
    WHERE id IN (
        SELECT id
        FROM cte_duplicates
        WHERE row_num > 1
    );

INSERT INTO dm_ascio.domain_host ( 
    domain_id,
    host_id
    )
    SELECT ht.source_domain_id, h.source_host_id 
    FROM host_temp ht
    JOIN dm_ascio.host h ON h.domain_id = ht.source_domain_id 
							AND ht.ns1_hostname = h.name; 

-- dm_ascio.contact, dm_ascio.contact_postal, dm_ascio.domain_contact
CREATE TEMP TABLE temp_contact_data AS
	WITH contact_data AS (
    SELECT 
     	gen_random_uuid() as SOURCE_contact_id,
        f.domain_name,
        CASE 
            WHEN f.own_orgname IS NULL THEN 'individual'
            ELSE 'organization'
        END AS type,
        f.own_organizationnumber AS org_reg,
        f.own_vatnumber AS org_vat,
        f.own_email AS email,
        f.own_phone AS phone,
        f.own_fax AS fax,
        f.own_country AS country,
        split_part(f.own_contactname, ', ', 2) AS first_name,
    	split_part(f.own_contactname, ', ', 1) AS last_name,
        f.own_orgname AS org_name,
        f.own_address1 AS address1,
        f.own_address2 AS address2,
        f.own_city AS city,
        f.own_postalcode AS postal_code,
        f.own_state AS state,
        FALSE AS is_international, -- Assuming ALL addresses are international; adjust as needed
        f.domain_own_handle as domain_handle,
        'registrant' as domain_contact_type --registrant admin tech billing
    FROM dm_ascio.domain_filtered f
    UNION ALL
    SELECT  
    gen_random_uuid() as SOURCE_contact_id,
        f.domain_name,
        CASE 
            WHEN f.own_orgname IS NULL THEN 'individual'
            ELSE 'organization'
        END AS type,
        f.own_organizationnumber AS org_reg,
        f.own_vatnumber AS org_vat,
        f.tec_email AS email,
        f.tec_phone AS phone,
        f.tec_fax AS fax,
        f.tec_country AS country,
        f.tec_firstname AS first_name,
        f.tec_lastname AS last_name,
        f.tec_orgname AS org_name,
        f.tec_address1 AS address1,
        f.tec_address2 AS address2,
        f.tec_city AS city,
        f.tec_postalcode AS postal_code,
        f.tec_state AS state,
        FALSE AS is_international,
        f.domain_tec_handle as domain_handle,
        'tech' as domain_contact_type --registrant admin tech billing
    FROM dm_ascio.domain_filtered f
    UNION ALL
    SELECT 
    gen_random_uuid() as SOURCE_contact_id,
        f.domain_name,
        CASE 
            WHEN f.own_orgname IS NULL THEN 'individual'
            ELSE 'organization'
        END AS type,
        f.own_organizationnumber AS org_reg,
        f.own_vatnumber AS org_vat,
        f.adm_email AS email,
        f.adm_phone AS phone,
        f.adm_fax AS fax,
        f.adm_country AS country,
        f.adm_firstname AS first_name,
        f.adm_lastname AS last_name,
        f.adm_orgname AS org_name,
        f.adm_address1 AS address1,
        f.adm_address2 AS address2,
        f.adm_city AS city,
        f.adm_postalcode AS postal_code,
        f.adm_state AS state,
        FALSE AS is_international,
        f.domain_adm_handle as domain_handle,
        'admin' as domain_contact_type --registrant admin tech billing
    FROM dm_ascio.domain_filtered f
    UNION ALL
    SELECT 
    gen_random_uuid() as SOURCE_contact_id,
        f.domain_name,
        CASE 
            WHEN f.own_orgname IS NULL THEN 'individual'
            ELSE 'organization'
        END AS type,
        f.own_organizationnumber AS org_reg,
        f.own_vatnumber AS org_vat,
        f.bil_email AS email,
        f.bil_phone AS phone,
        f.bil_fax AS fax,
        f.bil_country AS country,
        f.bil_firstname AS first_name,
        f.bil_lastname AS last_name,
        f.bil_orgname AS org_name,
        f.bil_address1 AS address1,
        f.bil_address2 AS address2,
        f.bil_city AS city,
        f.bil_postalcode AS postal_code,
        f.bil_state AS state,
        FALSE AS is_international,
        f.domain_bil_handle as domain_handle,
        'billing' as domain_contact_type --registrant admin tech billing
    FROM dm_ascio.domain_filtered f
    )
    SELECT * FROM contact_data;

INSERT INTO dm_ascio.contact (
    source_contact_id,
    type,
    org_reg,
    org_vat,
    email,
    phone,
    fax,
    country
    )
    SELECT 
    SOURCE_contact_id,
        type,
        org_reg,
        org_vat,
        email,
        phone,
        fax,
        country
    FROM temp_contact_data;

INSERT INTO dm_ascio.contact_postal (
    source_contact_id,
    is_international,
    first_name,
    last_name,
    org_name,
    address1,
    address2,
    city,
    postal_code,
    state
    )
    SELECT 
        source_contact_id,
        is_international,
        first_name, 
        last_name, 
        org_name,
        address1,
        address2,
        city,
        postal_code,
        state
    FROM temp_contact_data; 

INSERT INTO dm_ascio.domain_contact (
    source_domain_id,
    source_contact_id,
    domain_contact_type,
    is_local_presence,
    is_privacy_proxy,
    is_private,
    handle
    )
    SELECT 
        d.source_domain_id,
        t.source_contact_id,
        t.domain_contact_type,
        FALSE AS is_local_presence, -- Default value
        FALSE AS is_privacy_proxy,  -- Default value
        FALSE AS is_private,        -- Default value
        t.domain_handle  AS handle              
    FROM temp_contact_data t
    JOIN dm_ascio.domain d ON d.name = t.domain_name;

---- part that is not used 

INSERT INTO dm_ascio.secdns_key_data (
    flags,
    protocol,
    algorithm,
    public_key
	)
	SELECT 
	-- dnsseckey1_keytype, 257/256 
	    (f.dnsseckey1_keytype::INT & ~65471)::INT AS flags, -- keytag, 
	    f.dnsseckey1_protocol::INT AS protocol, -- Default value
	    f.dnsseckey1_keyalgorithm::INT AS algorithm,
	    f.dnsseckey1_publickey AS public_key
	FROM dm_ascio.domain_filtered f
	WHERE f.dnsseckey1_publickey IS NOT NULL and f.dnsseckey1_publickey <> ''
	UNION ALL
	SELECT 
	    (f.dnsseckey2_keytype::INT & ~65471)::INT AS flags,
	    f.dnsseckey2_protocol::INT AS protocol, 
	    f.dnsseckey2_keyalgorithm::INT AS algorithm,
	    f.dnsseckey2_publickey AS public_key
	FROM dm_ascio.domain_filtered f
	WHERE f.dnsseckey2_publickey IS NOT NULL and f.dnsseckey2_publickey <> ''
	UNION ALL
	SELECT 
	    (f.dnsseckey3_keytype::INT & ~65471)::INT AS flags,
	    f.dnsseckey3_protocol::INT AS protocol, 
	    f.dnsseckey3_keyalgorithm::INT AS algorithm,
	    f.dnsseckey3_publickey AS public_key
	FROM dm_ascio.domain_filtered f
	WHERE f.dnsseckey3_publickey IS NOT NULL and f.dnsseckey3_publickey <> '';

INSERT INTO dm_ascio.secdns_ds_data ( 
    key_tag,
    algorithm,
    digest_type,
    digest
	)
	SELECT 
	    f.dnsseckey1_keytag::INT AS key_tag,
	    f.dnsseckey1_keyalgorithm::INT AS algorithm,
	    f.dnsseckey1_digesttype::INT AS digest_type,
	    f.dnsseckey1_digest AS digest
	FROM dm_ascio.domain_filtered f
	WHERE f.dnsseckey1_keytag IS NOT NULL and f.dnsseckey1_keytag <> ''
		AND f.dnsseckey1_keyalgorithm <> ''
  		AND f.dnsseckey1_digesttype <> ''
	UNION ALL
	SELECT 
	    f.dnsseckey2_keytag::INT AS key_tag,
	    f.dnsseckey2_keyalgorithm::INT AS algorithm,
	    f.dnsseckey2_digesttype::INT AS digest_type,
	    f.dnsseckey2_digest AS digest
	FROM dm_ascio.domain_filtered f
	WHERE f.dnsseckey2_keytag IS NOT NULL and f.dnsseckey2_keytag <> ''
		AND f.dnsseckey2_keyalgorithm <> ''
  		AND f.dnsseckey2_digesttype <> ''
	UNION ALL
	SELECT 
	    f.dnsseckey3_keytag::INT AS key_tag,
	    f.dnsseckey3_keyalgorithm::INT AS algorithm,
	    f.dnsseckey3_digesttype::INT AS digest_type,
	    f.dnsseckey3_digest AS digest
	FROM dm_ascio.domain_filtered f
	WHERE f.dnsseckey3_keytag IS NOT NULL and f.dnsseckey3_keytag <> ''
		AND f.dnsseckey3_keyalgorithm <> ''
  		AND f.dnsseckey3_digesttype <> '';

INSERT INTO dm_ascio.domain_secdns (
    domain_id,
    ds_data_id,
    key_data_id
	)
	-- Insert DS data for dnsseckey1
	SELECT 
	    d.id AS domain_id,
	    ds.id AS ds_data_id,
	    NULL::UUID AS key_data_id
	FROM dm_ascio.domain_filtered f
	JOIN dm_ascio.domain d ON d.name = f.domain_name
	JOIN dm_ascio.secdns_ds_data ds ON ds.key_tag = f.dnsseckey1_keytag::INT
	WHERE f.dnsseckey1_digest IS NOT NULL
	  AND f.dnsseckey1_keytag <> '' -- Exclude empty strings
	  AND f.dnsseckey1_keyalgorithm <> ''
	  AND f.dnsseckey1_digesttype <> ''
	UNION ALL
	-- Insert DS data for dnsseckey2
	SELECT 
	    d.id AS domain_id,
	    ds.id AS ds_data_id,
	    NULL::UUID AS key_data_id
	FROM dm_ascio.domain_filtered f
	JOIN dm_ascio.domain d ON d.name = f.domain_name
	JOIN dm_ascio.secdns_ds_data ds ON ds.key_tag = f.dnsseckey2_keytag::INT
	WHERE f.dnsseckey2_digest IS NOT NULL
	  AND f.dnsseckey2_keytag <> '' -- Exclude empty strings
	  AND f.dnsseckey2_keyalgorithm <> ''
	  AND f.dnsseckey2_digesttype <> ''
	UNION ALL
	-- Insert DS data for dnsseckey3
	SELECT 
	    d.id AS domain_id,
	    ds.id AS ds_data_id,
	    NULL::UUID AS key_data_id
	FROM dm_ascio.domain_filtered f
	JOIN dm_ascio.domain d ON d.name = f.domain_name
	JOIN dm_ascio.secdns_ds_data ds ON ds.key_tag = f.dnsseckey3_keytag::INT
	WHERE f.dnsseckey3_digest IS NOT NULL
	  AND f.dnsseckey3_keytag <> '' -- Exclude empty strings
	  AND f.dnsseckey3_keyalgorithm <> ''
	  AND f.dnsseckey3_digesttype <> ''
	UNION ALL
	-- Insert Key data for dnsseckey1
	SELECT 
	    d.id AS domain_id,
	    NULL::UUID AS ds_data_id,
	    kd.id AS key_data_id
	FROM dm_ascio.domain_filtered f
	JOIN dm_ascio.domain d ON d.name = f.domain_name
	JOIN dm_ascio.secdns_key_data kd ON kd.public_key = f.dnsseckey1_publickey
	WHERE f.dnsseckey1_publickey IS NOT NULL
	  AND f.dnsseckey1_keytag <> '' -- Exclude empty strings
	  AND f.dnsseckey1_keyalgorithm <> ''
	UNION ALL
	-- Insert Key data for dnsseckey2
	SELECT 
	    d.id AS domain_id,
	    NULL::UUID AS ds_data_id,
	    kd.id AS key_data_id
	FROM dm_ascio.domain_filtered f
	JOIN dm_ascio.domain d ON d.name = f.domain_name
	JOIN dm_ascio.secdns_key_data kd ON kd.public_key = f.dnsseckey2_publickey
	WHERE f.dnsseckey2_publickey IS NOT NULL
	  AND f.dnsseckey2_keytag <> '' -- Exclude empty strings
	  AND f.dnsseckey2_keyalgorithm <> ''
	UNION ALL
	-- Insert Key data for dnsseckey3
	SELECT 
	    d.id AS domain_id,
	    NULL::UUID AS ds_data_id,
	    kd.id AS key_data_id
	FROM dm_ascio.domain_filtered f
	JOIN dm_ascio.domain d ON d.name = f.domain_name
	JOIN dm_ascio.secdns_key_data kd ON kd.public_key = f.dnsseckey3_publickey
	WHERE f.dnsseckey3_publickey IS NOT NULL
	  AND f.dnsseckey3_keytag <> '' -- Exclude empty strings
	  AND f.dnsseckey3_keyalgorithm <> '';

-- 3. intermediate schema 
INSERT INTO itdp."domain" ( 
    tld,
    dm_source,
    source_domain_id,
    id, 
    tenant_customer_id,
    accreditation_tld_id,
    "name",
    auth_info,
    roid,
    ry_created_date,
    ry_expiry_date,
    ry_updated_date,
    ry_transfered_date,
    deleted_date,
    expiry_date,
    status_id,
    auto_renew,
    registration_period,
    dm_status,
    uname,
    "language",
    secdns_max_sig_life,
    tdp_min_namesrvers_issue
    )
    SELECT 
        CASE WHEN name like '%.in' 
                THEN SUBSTRING(name FROM POSITION('.' IN name) + 1)
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--h2brj9c'
                THEN 'in'
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--31bp1cdl0b3hd3b.xn--h2brj9c'
                THEN 'co.in'
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--11baaz5fza8cvdxc4cc.xn--h2brj9c'
                THEN 'firm.in'
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--11bt3bp2be2b8hf.xn--i1b1b4ch5i.xn--h2brj9c'
                THEN 'gen.in'
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--11bt3bp2be2b8hf.xn--i1b1b4ch5i.xn--h2brj9c'
                THEN 'gen.in'
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--i1bk1fb7bj4abn7d8c7e8cfc.xn--h2brj9c'
                THEN 'ind.in'
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--i1b1b4ch5i.xn--h2brj9c'
                THEN 'ind.in'
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--11b8c9aj7d.xn--i1b1b4ch5i.xn--h2brj9c'
                THEN 'net.in'
            WHEN SUBSTRING(name FROM POSITION('.' IN name) + 1) = 'xn--l1b6drbs0c.xn--h2brj9c'
                THEN 'org.in'	
            ELSE NULL 
        END tld, 
        'ascio' AS dm_source,
        source_domain_id, 
        d.id,
        NULL AS tenant_customer_id,
        NULL AS accreditation_tld_id,
        "name",
        auth_info,
        roid,
        ry_created_date,
        ry_expiry_date,
        ry_updated_date,
        ry_transfered_date,
        deleted_date,
        d.expiry_date,
        CASE WHEN drs.status is not NULL 
            THEN tc_id_from_name('itdp.domain_status', 'RGP') 
            ELSE tc_id_from_name('itdp.domain_status', 'Active')
        END status_id, 
        auto_renew,
        1 AS registration_period,
        NULL AS dm_status,
        uname,
        idn_lang AS "language",
        secdns_max_sig_life,
        false AS tdp_min_namesrvers_issue
    FROM dm_ascio."domain" d
    LEFT JOIN dm_ascio.domain_rgp_status drs 
        ON drs.domain_id = d.source_domain_id;

INSERT INTO itdp.host( 
	tld,
	dm_source,
	source_host_id,
	source_domain_id,
	id,
	itdp_domain_id,
	tenant_customer_id,
	name,
	host_id_unique_name,
	host_id_unique_name_tdp)
	SELECT
		CASE WHEN d.name like '%xn--%' 
           THEN 'ind.in'
            ELSE SUBSTRING(d.name FROM POSITION('.' IN d.name) + 1)
        end tld,
        'ascio' AS dm_source,
		h.source_host_id AS source_host_id,
		d.source_domain_id AS source_domain_id,
		h.id,
		itdp_d.id AS itdp_domain_id,
		'c233d9f3-54aa-44c2-b28d-7789d63bc4c6'::UUID AS tenant_customer_id,
		h."name",
		NULL AS host_id_unique_name,
		NULL AS host_id_unique_name_tdp
	FROM dm_ascio.host h
	JOIN dm_ascio.domain_host dh ON h.source_host_id = dh.host_id 
	JOIN dm_ascio.domain d ON dh.domain_id = d.source_domain_id
	JOIN itdp."domain" itdp_d ON itdp_d.id = d.id 
		AND dm_source = 'ascio'
	WHERE h."name" is not NULL
		AND h."name" <> ''; 

INSERT INTO itdp.contact( 
	tld,
	dm_source,
	source_contact_id,
	source_domain_id,
	id,
	itdp_domain_id,
	type_id,
	title,
	org_reg,
	org_vat,
	org_duns,
	tenant_customer_id,
	email,
	phone,
	fax,
	country,
	language,
	tdp_contact_country_issue,
	tdp_data_source,
	placeholder,
	domain_contact_type_name,
	is_private)
	SELECT
	  	CASE WHEN d.name like '%xn--%' 
           THEN 'ind.in'
            ELSE SUBSTRING(d.name FROM POSITION('.' IN d.name) + 1)
    	END tld,
		'ascio' AS dm_source,
		dc.source_contact_id as source_contact_id, -- MUST BE UUIS 
		dc.source_domain_id AS source_domain_id,
		dc.source_contact_id as id, 
		itdp_d.id AS itdp_domain_id,
		itdp_ct.id as type_id, 
		NULL as title, 
		c.org_reg,
		c.org_vat,
		c.org_duns, 
		'c233d9f3-54aa-44c2-b28d-7789d63bc4c6'::UUID AS tenant_customer_id,
		LOWER(c.email), 
		c.phone,
		c.fax,
		UPPER(c.country),
		c.language, 
		NULL as tdp_contact_country_issue,
		NULL as tdp_data_source,
		NULL as placeholder,
		dc.domain_contact_type as domain_contact_type_name,
		false as is_private,
		c.contact_handle
	FROM dm_ascio.domain_contact dc
	JOIN dm_ascio.domain d ON d.source_domain_id = dc.source_domain_id
	JOIN dm_ascio.contact c ON c.source_contact_id = dc.source_contact_id
	JOIN itdp.contact_type itdp_ct ON itdp_ct.name = c.type
	JOIN itdp."domain" itdp_d ON itdp_d.source_domain_id = d.source_domain_id;
	
INSERT INTO itdp.contact_postal( 
	tld,
	dm_source,
	id,
	source_contact_id,
	contact_id,
	is_international,
	first_name,
	last_name,
	org_name,
	address1,
	address2,
	address3,
	city,
	postal_code,
	state)
	SELECT
		CASE WHEN d.name like '%xn--%' 
           THEN 'ind.in'
            ELSE SUBSTRING(d.name FROM POSITION('.' IN d.name) + 1)
		END tld,
	    'ascio' AS dm_source,
	    cp.id, 
	    dc.source_contact_id as source_contact_id,
	    dc.source_contact_id as contact_id,
	    cp.is_international,
	    cp.first_name,
	    cp.last_name,
	    cp.org_name,
	    cp.address1,
	    cp.address2,
	    cp.address3,
	    cp.city,
	    cp.postal_code,
	    cp.state
	FROM dm_ascio.contact_postal cp
	JOIN dm_ascio.contact c ON cp.source_contact_id = c.source_contact_id
	JOIN dm_ascio.domain_contact dc ON c.source_contact_id = dc.source_contact_id
	JOIN dm_ascio.domain d ON d.source_domain_id = dc.source_domain_id; 
	
INSERT INTO itdp.domain_lock( 
	id,
	tld,
	dm_source,
	domain_id,
	type_id,
	is_internal,
	created_date,
	expiry_date)
	SELECT
		l.id, 
		CASE WHEN d.name like '%xn--%' 
           THEN 'ind.in'
            ELSE SUBSTRING(d.name FROM POSITION('.' IN d.name) + 1) 
		END tld,
		'ascio' AS dm_source,
		d.id,  
		itdp_l.id as type_id,
		false as is_internal, 
		NULL as created_date,
		NULL as expiry_date
	FROM dm_ascio.domain_lock l
	JOIN dm_ascio.domain d ON d.source_domain_id = l.domain_id
	JOIN itdp.lock_type itdp_l ON itdp_l.name = REGEXP_REPLACE(l.lock, '_lock$', '');

INSERT INTO itdp.host_addr( 
	tld,
	dm_source,
	source_host_id,
	id,
	itdp_host_id,
	address
	)
	SELECT 
		CASE WHEN d.name like '%xn--%' 
           THEN 'ind.in'
            ELSE SUBSTRING(d.name FROM POSITION('.' IN d.name) + 1) 
		END tld,
		'ascio' AS dm_source,
		h.source_host_id AS source_host_id,
		a.id,
		h.id as itdp_host_id,
		a.address
	FROM dm_ascio.host h
	JOIN dm_ascio.host_addr a 
		ON a.host_id = h.source_host_id
	JOIN dm_ascio.domain d ON h.domain_id = d.source_domain_id; 
