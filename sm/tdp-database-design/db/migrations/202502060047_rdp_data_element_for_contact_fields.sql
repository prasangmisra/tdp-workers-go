INSERT INTO data_element (name, descr, group_id)
VALUES
    -- Registrant contact data elements
    ('org_name', 'Name of the registrant organization', tc_id_from_name('data_element_group', 'registrant')),
    ('address2', 'Secondary address of the registrant', tc_id_from_name('data_element_group', 'registrant')),
    ('address3', 'Tertiary address of the registrant', tc_id_from_name('data_element_group', 'registrant')),
    ('city', 'City of the registrant', tc_id_from_name('data_element_group', 'registrant')),
    ('state', 'State of the registrant', tc_id_from_name('data_element_group', 'registrant')),
    ('postal_code', 'Postal code of the registrant', tc_id_from_name('data_element_group', 'registrant')),
    ('country', 'Country of the registrant', tc_id_from_name('data_element_group', 'registrant')),
    ('fax', 'Fax number of the registrant', tc_id_from_name('data_element_group', 'registrant')),
    ('pw', 'Password of the registrant', tc_id_from_name('data_element_group', 'registrant')),

    -- Admin contact data elements
    ('org_name', 'Name of the admin organization', tc_id_from_name('data_element_group', 'admin')),
    ('address2', 'Secondary address of the admin contact', tc_id_from_name('data_element_group', 'admin')),
    ('address3', 'Tertiary address of the admin contact', tc_id_from_name('data_element_group', 'admin')),
    ('city', 'City of the admin contact', tc_id_from_name('data_element_group', 'admin')),
    ('state', 'State of the admin contact', tc_id_from_name('data_element_group', 'admin')),
    ('postal_code', 'Postal code of the admin contact', tc_id_from_name('data_element_group', 'admin')),
    ('country', 'Country of the admin contact', tc_id_from_name('data_element_group', 'admin')),
    ('fax', 'Fax number of the admin contact', tc_id_from_name('data_element_group', 'admin')),
    ('pw', 'Password of the admin contact', tc_id_from_name('data_element_group', 'admin')),

    -- Tech contact data elements
    ('org_name', 'Name of the tech organization', tc_id_from_name('data_element_group', 'tech')),
    ('address2', 'Secondary address of the tech contact', tc_id_from_name('data_element_group', 'tech')),
    ('address3', 'Tertiary address of the tech contact', tc_id_from_name('data_element_group', 'tech')),
    ('city', 'City of the tech contact', tc_id_from_name('data_element_group', 'tech')),
    ('state', 'State of the tech contact', tc_id_from_name('data_element_group', 'tech')),
    ('postal_code', 'Postal code of the tech contact', tc_id_from_name('data_element_group', 'tech')),
    ('country', 'Country of the tech contact', tc_id_from_name('data_element_group', 'tech')),
    ('fax', 'Fax number of the tech contact', tc_id_from_name('data_element_group', 'tech')),
    ('pw', 'Password of the tech contact', tc_id_from_name('data_element_group', 'tech')),

    -- Billing contact data elements
    ('org_name', 'Name of the billing organization', tc_id_from_name('data_element_group', 'billing')),
    ('address2', 'Secondary address of the billing contact', tc_id_from_name('data_element_group', 'billing')),
    ('address3', 'Tertiary address of the billing contact', tc_id_from_name('data_element_group', 'billing')),
    ('city', 'City of the billing contact', tc_id_from_name('data_element_group', 'billing')),
    ('state', 'State of the billing contact', tc_id_from_name('data_element_group', 'billing')),
    ('postal_code', 'Postal code of the billing contact', tc_id_from_name('data_element_group', 'billing')),
    ('country', 'Country of the billing contact', tc_id_from_name('data_element_group', 'billing')),
    ('fax', 'Fax number of the billing contact', tc_id_from_name('data_element_group', 'billing')),
    ('pw', 'Password of the billing contact', tc_id_from_name('data_element_group', 'billing'))
ON CONFLICT DO NOTHING;
