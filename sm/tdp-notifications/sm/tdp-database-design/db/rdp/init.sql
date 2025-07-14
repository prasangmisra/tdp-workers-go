INSERT INTO permission_group (name, descr)
VALUES
    ('collection', 'Permissions related to data collection'),
    ('transmission', 'Permissions related to data transmission'),
    ('publication', 'Permissions related to publication to RDDS');

INSERT INTO permission (name, descr, group_id)
VALUES
    ('must_collect', 'Data element must always be collected', tc_id_from_name('permission_group', 'collection')),
    ('may_collect', 'Data element mey be collected', tc_id_from_name('permission_group', 'collection')),
    ('must_not_collect', 'Data element must never be collected', tc_id_from_name('permission_group', 'collection')),
    ('transmit_to_registry', 'Data element will be sent to registry', tc_id_from_name('permission_group', 'transmission')),
    ('transmit_to_escrow', 'Data element will be sent to escrow provider', tc_id_from_name('permission_group', 'transmission')),
    ('available_for_consent', 'Data element will be available for consent to publish in RDDS', tc_id_from_name('permission_group', 'publication')),
    ('publish_by_default', 'Data element will be published in RDDS', tc_id_from_name('permission_group', 'publication'));


WITH registrant_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('registrant', 'Data element related to registrant contact')
    RETURNING id
), admin_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('admin', 'Data element related to admin contact')
    RETURNING id
), tech_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('tech', 'Data element related to tech contact')
    RETURNING id
), billing_de AS (
    INSERT INTO data_element (name, descr)
    VALUES ('billing', 'Data element related to billing contact')
    RETURNING id
)
INSERT INTO data_element (name, descr, parent_id)
VALUES
    -- Registrant contact data elements
    ('first_name', 'First name of the registrant', (SELECT id FROM registrant_de)),
    ('last_name', 'Last name of the registrant', (SELECT id FROM registrant_de)),
    ('email', 'Email address of the registrant', (SELECT id FROM registrant_de)),
    ('address1', 'Primary address of the registrant', (SELECT id FROM registrant_de)),
    ('phone', 'Phone number of the registrant', (SELECT id FROM registrant_de)),
    ('org_name', 'Name of the registrant organization', (SELECT id FROM registrant_de)),
    ('address2', 'Secondary address of the registrant', (SELECT id FROM registrant_de)),
    ('address3', 'Tertiary address of the registrant', (SELECT id FROM registrant_de)),
    ('city', 'City of the registrant', (SELECT id FROM registrant_de)),
    ('state', 'State of the registrant', (SELECT id FROM registrant_de)),
    ('postal_code', 'Postal code of the registrant', (SELECT id FROM registrant_de)),
    ('country', 'Country of the registrant', (SELECT id FROM registrant_de)),
    ('fax', 'Fax number of the registrant', (SELECT id FROM registrant_de)),
    ('pw', 'Password of the registrant', (SELECT id FROM registrant_de)),

    -- Admin contact data elements
    ('first_name', 'First name of the admin contact', (SELECT id FROM admin_de)),
    ('last_name', 'Last name of the admin contact', (SELECT id FROM admin_de)),
    ('email', 'Email address of the admin contact', (SELECT id FROM admin_de)),
    ('address1', 'Primary address of the admin contact', (SELECT id FROM admin_de)),
    ('phone', 'Phone number of the admin contact', (SELECT id FROM admin_de)),
    ('org_name', 'Name of the admin organization', (SELECT id FROM admin_de)),
    ('address2', 'Secondary address of the admin contact', (SELECT id FROM admin_de)),
    ('address3', 'Tertiary address of the admin contact', (SELECT id FROM admin_de)),
    ('city', 'City of the admin contact', (SELECT id FROM admin_de)),
    ('state', 'State of the admin contact', (SELECT id FROM admin_de)),
    ('postal_code', 'Postal code of the admin contact', (SELECT id FROM admin_de)),
    ('country', 'Country of the admin contact', (SELECT id FROM admin_de)),
    ('fax', 'Fax number of the admin contact', (SELECT id FROM admin_de)),
    ('pw', 'Password of the admin contact', (SELECT id FROM admin_de)),

    -- Tech contact data elements
    ('first_name', 'First name of the tech contact', (SELECT id FROM tech_de)),
    ('last_name', 'Last name of the tech contact', (SELECT id FROM tech_de)),
    ('email', 'Email address of the tech contact', (SELECT id FROM tech_de)),
    ('address1', 'Primary address of the tech contact', (SELECT id FROM tech_de)),
    ('phone', 'Phone number of the tech contact', (SELECT id FROM tech_de)),
    ('org_name', 'Name of the tech organization', (SELECT id FROM tech_de)),
    ('address2', 'Secondary address of the tech contact', (SELECT id FROM tech_de)),
    ('address3', 'Tertiary address of the tech contact', (SELECT id FROM tech_de)),
    ('city', 'City of the tech contact', (SELECT id FROM tech_de)),
    ('state', 'State of the tech contact', (SELECT id FROM tech_de)),
    ('postal_code', 'Postal code of the tech contact', (SELECT id FROM tech_de)),
    ('country', 'Country of the tech contact', (SELECT id FROM tech_de)),
    ('fax', 'Fax number of the tech contact', (SELECT id FROM tech_de)),
    ('pw', 'Password of the tech contact', (SELECT id FROM tech_de)),

    -- Billing contact data elements
    ('first_name', 'First name of the billing contact', (SELECT id FROM billing_de)),
    ('last_name', 'Last name of the billing contact', (SELECT id FROM billing_de)),
    ('email', 'Email address of the billing contact', (SELECT id FROM billing_de)),
    ('address1', 'Primary address of the billing contact', (SELECT id FROM billing_de)),
    ('phone', 'Phone number of the billing contact', (SELECT id FROM billing_de)),
    ('org_name', 'Name of the billing organization', (SELECT id FROM billing_de)),
    ('address2', 'Secondary address of the billing contact', (SELECT id FROM billing_de)),
    ('address3', 'Tertiary address of the billing contact', (SELECT id FROM billing_de)),
    ('city', 'City of the billing contact', (SELECT id FROM billing_de)),
    ('state', 'State of the billing contact', (SELECT id FROM billing_de)),
    ('postal_code', 'Postal code of the billing contact', (SELECT id FROM billing_de)),
    ('country', 'Country of the billing contact', (SELECT id FROM billing_de)),
    ('fax', 'Fax number of the billing contact', (SELECT id FROM billing_de)),
    ('pw', 'Password of the billing contact', (SELECT id FROM billing_de));
