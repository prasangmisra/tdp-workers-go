--
-- view: v_subscription
-- description: this view lists all subscriptions with coresponding notification typess
--

CREATE OR REPLACE VIEW v_subscription AS
SELECT
    s.id,
    s.descr AS description,
    s.metadata,
    s.tags,
    s.created_date,
    s.updated_date,
    s.deleted_date,
    ss.name AS status,
    s.tenant_id,
    s.tenant_customer_id,
    sct.name AS type,
    s.notification_email,
    swc.webhook_url,
    swc.signing_secret,
    ARRAY_AGG(nt.name) AS notifications
FROM subscription s
         JOIN subscription_status ss ON ss.id = s.status_id
         LEFT JOIN subscription_notification_type snt ON snt.subscription_id = s.id
         LEFT JOIN notification_type nt ON nt.id = snt.type_id
         LEFT JOIN subscription_channel sc ON sc.subscription_id = s.id
         LEFT JOIN subscription_webhook_channel swc ON swc.subscription_id = s.id
         LEFT JOIN subscription_channel_type sct ON sct.id = sc.type_id
GROUP BY s.id, ss.name, swc.webhook_url, swc.signing_secret, sct.name;

--
-- view: v_subscription_channel
-- description: this view lists all subscription channels with coresponding notification typess
--

CREATE OR REPLACE VIEW v_subscription_channel AS
SELECT
    sc.id,
    swc.webhook_url,
    swc.signing_secret,
    sct.name AS type,
    sc.subscription_id,
    vs.status AS subscription_status,
    vs.tenant_id,
    vs.tenant_customer_id,
    vs.notifications
FROM subscription_channel sc
LEFT JOIN subscription_email_channel sec ON sec.id = sc.id
LEFT JOIN subscription_webhook_channel swc ON swc.id = sc.id
LEFT JOIN subscription_poll_channel spc ON spc.id = sc.id
JOIN subscription_channel_type sct ON sct.id = sc.type_id
JOIN v_subscription vs ON vs.id = sc.subscription_id;


--
-- view: v_migration
-- description: this view lists all migrations with coresponding migration names
--

CREATE OR REPLACE VIEW v_migration AS
SELECT
    m.version_number,
    COUNT(m.version_number) AS total_migrations,
    STRING_AGG(m.name, ', ' ORDER BY m.applied_date) AS migration_names,
    MIN(m.applied_date) AS first_migration_date,
    MAX(m.applied_date) AS last_migration_date
FROM
    migration m
GROUP BY
    m.version_number
ORDER BY
    MAX(m.applied_date) DESC;
