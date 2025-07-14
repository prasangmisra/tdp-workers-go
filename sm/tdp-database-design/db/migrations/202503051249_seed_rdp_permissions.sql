INSERT INTO permission_group (name, descr)
VALUES
    ('collection', 'Permissions related to data collection'),
    ('transmission', 'Permissions related to data transmission'),
    ('consent', 'Permissions related to data consent') ON CONFLICT DO NOTHING;

INSERT INTO permission (name, descr, group_id)
VALUES
    ('must_collect', 'Data element must always be collected', tc_id_from_name('permission_group', 'collection')),
    ('may_collect', 'Data element mey be collected', tc_id_from_name('permission_group', 'collection')),
    ('must_not_collect', 'Data element must never be collected', tc_id_from_name('permission_group', 'collection')),
    ('transmit_to_registry', 'Data element will be sent to registry', tc_id_from_name('permission_group', 'transmission')),
    ('transmit_to_escrow', 'Data element will be sent to escrow provider', tc_id_from_name('permission_group', 'transmission')),
    ('available_for_consent', 'Data element will be available for consent to publish in RDDS', tc_id_from_name('permission_group', 'consent')) ON CONFLICT DO NOTHING;
