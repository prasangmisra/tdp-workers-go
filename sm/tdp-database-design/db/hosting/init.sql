INSERT INTO hosting_component_type (name, descr)
VALUES
    ('container', 'Docker Container'),
    ('database', 'Database');


INSERT INTO hosting_component (type_id, name, descr)
VALUES
    (tc_id_from_name('hosting_component_type', 'container'), 'wordpress', 'Hosted Wordpress'),
    (tc_id_from_name('hosting_component_type', 'container'), 'phpmyadmin', 'PHPMyAdmin'),
    (tc_id_from_name('hosting_component_type', 'database'), 'mysqldb', 'MySQL Database');


WITH product AS (
    SELECT * FROM hosting_product WHERE name = 'Wordpress'
)
INSERT INTO hosting_product_component (product_id, component_id)
VALUES
    ((SELECT id from product), (SELECT id FROM hosting_component WHERE name = 'wordpress')),
    ((SELECT id from product), (SELECT id FROM hosting_component WHERE name = 'phpmyadmin')),
    ((SELECT id from product), (SELECT id FROM hosting_component WHERE name = 'mysqldb'));

INSERT INTO hosting_status (name, descr)
VALUES
    ('Pending DNS', 'Hosting is pending for DNS Setup'),
    ('Pending Certificate Setup', 'Hosting is pending for Certificate Setup'),
    ('Requested', 'Hosting was requested'),
    ('In progress', 'Hosting creation is in progress'),
    ('Completed', 'Hosting creation is completed'),
    ('Failed', 'Hosting creation failed'),
    ('Failed Certificate Renewal', 'Hosting failed on certificate renewal'),
    ('Cancelled', 'Hosting creation was cancelled');
