-- populates domain id column and sets to be not null

UPDATE order_item_update_domain oiud
SET domain_id = d.id 
FROM domain d
WHERE oiud.name = d.name AND oiud.domain_id IS NULL;

UPDATE order_item_renew_domain oird
SET domain_id = d.id 
FROM domain d
WHERE oird.name = d.name AND oird.domain_id IS NULL;

ALTER TABLE order_item_update_domain ALTER COLUMN domain_id SET NOT NULL;
ALTER TABLE order_item_renew_domain ALTER COLUMN domain_id SET NOT NULL;
