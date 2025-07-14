DROP VIEW IF EXISTS v_tenant_customer CASCADE ;
CREATE OR REPLACE VIEW v_tenant_customer AS 
    SELECT 
        tc.tenant_id,
        tc.customer_id,
        t.name AS tenant_name,
        t.descr AS tenant_descr,
        tc.customer_number,
        tc.id AS id,
        c.name AS name,
        c.descr AS descr,
        c.created_date AS customer_created_date,
        c.updated_date AS customer_updated_date,
        tc.created_date AS tenant_customer_created_date,
        tc.updated_date AS tenant_customer_updated_date
    FROM tenant_customer tc 
        JOIN tenant t ON t.id = tc.tenant_id 
        JOIN customer c ON c.id = tc.customer_id;

DROP VIEW IF EXISTS v_customer_user;
CREATE OR REPLACE VIEW v_customer_user AS 
    SELECT 
        cu.customer_id,
        cu.user_id,
        c.name AS customer_name,
        c.descr AS customer_descr,
        cu.id AS id,
        u.email AS email,
        u.name AS name,
        u.created_date AS user_created_date,
        u.updated_date AS user_updated_date,
        cu.created_date AS customer_user_created_date,
        cu.updated_date AS customer_user_updated_date
    FROM customer_user cu 
        JOIN customer c ON c.id = cu.customer_id
        JOIN "user" u ON u.id = cu.user_id 
;


