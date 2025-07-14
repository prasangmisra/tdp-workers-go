-- Remove duplicate host_addr entries
DO $$ 
BEGIN
IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'host_addr') THEN
DELETE FROM host_addr hd
    USING host_addr new_hd
WHERE hd.id < new_hd.id AND hd.host_id = new_hd.host_id AND hd.address = new_hd.address;
END IF;
END $$;

-- Remove duplicate order_item_create_host_addr entries
DO $$ 
BEGIN
IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'order_item_create_host_addr') THEN
DELETE FROM order_item_create_host_addr ohd
    USING order_item_create_host_addr new_ohd
WHERE ohd.id < new_ohd.id AND ohd.host_id = new_ohd.host_id AND ohd.address = new_ohd.address;
END IF;
END $$;

-- Remove duplicate create_domain_nameserver_addr entries
DO $$ 
BEGIN
IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'create_domain_nameserver_addr') THEN
DELETE FROM create_domain_nameserver_addr cnd
    USING create_domain_nameserver_addr new_cnd
WHERE cnd.id < new_cnd.id AND cnd.nameserver_id = new_cnd.nameserver_id AND cnd.addr = new_cnd.addr;
END IF;
END $$;


-- add constraints to host_addr and order_item_create_host_addr
ALTER TABLE IF EXISTS host_addr
    DROP CONSTRAINT IF EXISTS unique_host_addr_and_id,
    DROP CONSTRAINT IF EXISTS host_addr_host_id_address_key,
    ADD CONSTRAINT host_addr_host_id_address_key UNIQUE (host_id, address);

ALTER TABLE IF EXISTS order_item_create_host_addr
    DROP CONSTRAINT IF EXISTS unique_order_item_create_host_addr_and_id,
    DROP CONSTRAINT IF EXISTS order_item_create_host_addr_host_id_address_key,
    ADD CONSTRAINT order_item_create_host_addr_host_id_address_key UNIQUE (host_id, address);

ALTER TABLE IF EXISTS create_domain_nameserver_addr
    DROP CONSTRAINT IF EXISTS unique_create_domain_nameserver_addr_and_id,
    DROP CONSTRAINT IF EXISTS create_domain_nameserver_addr_nameserver_id_addr_key,
    ADD CONSTRAINT create_domain_nameserver_addr_nameserver_id_addr_key UNIQUE (nameserver_id, addr);

