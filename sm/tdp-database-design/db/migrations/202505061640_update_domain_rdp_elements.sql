WITH domain_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('domain', 'Data element related to domain object')
    RETURNING id
)
UPDATE data_element SET parent_id = (SELECT id FROM domain_de)
WHERE name IN (
    'registrant',
    'admin',
    'tech',
    'billing'
);
