--
-- view: v_notification
-- description: this view lists all notifications with coresponding subscription channel
--

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
    s.id AS subscription_id,
    swc.webhook_url,
    swc.signing_secret,
    s.status_id,
    template.subject AS email_subject,
    template.content AS email_template
FROM notification_delivery nd
JOIN notification_status ns ON ns.id = nd.status_id
JOIN notification n ON n.id = nd.notification_id
JOIN notification_type nt ON nt.id = n.type_id
LEFT JOIN subscription_poll_channel spc ON spc.id = nd.channel_id
LEFT JOIN subscription_webhook_channel swc ON swc.id = nd.channel_id
LEFT JOIN subscription_email_channel sec ON sec.id = nd.channel_id
JOIN subscription_channel_type sct ON sct.id IN (swc.type_id, sec.type_id, spc.type_id)
JOIN subscription s ON s.id IN (swc.subscription_id, sec.subscription_id, spc.subscription_id)
JOIN subscription_status ss ON ss.id = s.status_id
LEFT JOIN LATERAL (
    SELECT
        vnt.subject,
        vnt.content
    FROM v_notification_template vnt
    WHERE vnt.notification_type_id = nt.id
      AND (
          (vnt.tenant_id = n.tenant_id AND vnt.tenant_customer_id = n.tenant_customer_id)
          OR (vnt.tenant_id = n.tenant_id AND vnt.tenant_customer_id IS NULL)
          OR (vnt.tenant_id IS NULL AND vnt.tenant_customer_id IS NULL)
      )
    ORDER BY
        CASE
            WHEN vnt.tenant_id = n.tenant_id AND vnt.tenant_customer_id = n.tenant_customer_id THEN 1
            WHEN vnt.tenant_id = n.tenant_id AND vnt.tenant_customer_id IS NULL THEN 2
            WHEN vnt.tenant_id IS NULL AND vnt.tenant_customer_id IS NULL THEN 3
            ELSE 4
        END
    LIMIT 1
) template ON sct.name = 'email'
WHERE ss.name NOT IN ('paused', 'deactivated');

