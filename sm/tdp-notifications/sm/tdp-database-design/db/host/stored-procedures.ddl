
-- function: get_host_addrs()
-- description: returns a sorted array containing all addresses an host
CREATE OR REPLACE FUNCTION get_host_addrs(p_id UUID) RETURNS INET[] AS $$
DECLARE
    addrs INET[];
BEGIN
    SELECT INTO addrs ARRAY_AGG(address ORDER BY address)
    FROM ONLY host_addr
    WHERE host_id = p_id;

    RETURN COALESCE(addrs, '{}'); -- return empty array Instead of NULL
END;
$$ LANGUAGE plpgsql STABLE;


-- function: get_order_host_addrs()
-- description: returns a sorted array containing all addresses an order host
CREATE OR REPLACE FUNCTION get_order_host_addrs(p_id UUID) RETURNS INET[] AS $$
DECLARE
    addrs INET[];
BEGIN
    SELECT INTO addrs ARRAY_AGG(address ORDER BY address)
    FROM ONLY order_host_addr
    WHERE host_id = p_id;

    RETURN COALESCE(addrs, '{}'); -- return empty array Instead of NULL
END;
$$ LANGUAGE plpgsql STABLE;
