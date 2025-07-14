-- Cascade drop of existing views before recreating v_subscription view
DROP VIEW IF EXISTS v_subscription_channel;
DROP VIEW IF EXISTS v_subscription;

-- Recreate v_subscription with deleted_date field
--
--
-- view: v_subscription
-- description: this view lists all subscriptions with corresponding notification types
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


-- Recreate v_subscription_channel as it was originally defined
--
-- view: v_subscription_channel
-- description: this view lists all subscription channels with corresponding notification types
--

CREATE OR REPLACE VIEW v_subscription_channel AS
SELECT
    sc.id,
    sec.email,
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
