--
-- Add a column to store the failure reason for notifications
--

--
-- Add column status_reason to table notification_delivery
--

ALTER TABLE IF EXISTS notification_delivery
ADD COLUMN IF NOT EXISTS status_reason TEXT NULL;

--
-- Add column status_reason to view v_notification
--

DROP VIEW IF EXISTS v_notification;
CREATE OR REPLACE VIEW v_notification AS
SELECT
    nd.id,
    n.id AS notification_id,
    nt.name AS type,
    n.payload,
    n.created_date,
    n.tenant_id,
    n.tenant_customer_id,
    ns.name AS status,
    nd.retries,
    nd.status_reason,
    sct.name AS channel_type,
    sc.subscription_id,
    swc.webhook_url,
    swc.signing_secret,
    s.status_id
FROM notification_delivery nd
JOIN notification_status ns ON ns.id = nd.status_id
JOIN subscription_channel sc ON sc.id = nd.channel_id
JOIN subscription_channel_type sct ON sct.id = sc.type_id
JOIN notification n ON n.id = nd.notification_id
JOIN notification_type nt ON nt.id = n.type_id
JOIN subscription s on s.id = sc.subscription_id
LEFT JOIN subscription_email_channel sec ON sec.id = sc.id
LEFT JOIN subscription_webhook_channel swc ON swc.id = sc.id
WHERE s.status_id != tc_id_from_name('subscription_status', 'paused') AND
s.status_id != tc_id_from_name('subscription_status', 'deactivated');