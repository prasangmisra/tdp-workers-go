CREATE UNIQUE INDEX ON order_item_update_domain(name,accreditation_tld_id)
    WHERE status_id = tc_id_from_name('order_item_status','pending')
        OR status_id = tc_id_from_name('order_item_status','ready');

-- Cancel all duplicate orders for the same domain
-- with status pending or ready
WITH DuplicateOrders AS (
    SELECT 
        name, 
        accreditation_tld_id
    FROM order_item_transfer_away_domain
    WHERE status_id IN (
        tc_id_from_name('order_item_status', 'pending'),
        tc_id_from_name('order_item_status', 'ready')
    )
    GROUP BY 
        name, 
        accreditation_tld_id
    HAVING 
        COUNT(*) > 1
) 
UPDATE order_item_transfer_away_domain
SET 
    status_id = tc_id_from_name('order_item_status', 'canceled')
WHERE 
    (name, accreditation_tld_id) IN (
        SELECT 
            name, 
            accreditation_tld_id 
        FROM DuplicateOrders
    )
    AND status_id IN (
        tc_id_from_name('order_item_status', 'pending'),
        tc_id_from_name('order_item_status', 'ready')
    );

CREATE UNIQUE INDEX ON order_item_transfer_away_domain(name,accreditation_tld_id)
    WHERE status_id = tc_id_from_name('order_item_status','pending')
        OR status_id = tc_id_from_name('order_item_status','ready');
