CREATE OR REPLACE VIEW v_host AS
SELECT 
    h.id,
    h.tenant_customer_id,
    h.name,
    h.domain_id AS parent_domain_id,
    d.name AS parent_domain_name,
    h.tags,
    h.metadata,
    addr.addresses
FROM ONLY host h
LEFT JOIN 
    domain d ON h.domain_id = d.id
LEFT JOIN LATERAL (
    SELECT ARRAY_AGG(address) AS addresses
    FROM ONLY host_addr
    WHERE host_id = h.id
) addr ON TRUE;
