-- Migration: Extend v_notification view to include channel-specific data (email, webhook_url, signing_secret)

-- Drop existing view
DROP VIEW IF EXISTS v_notification;

-- Create the updated view
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
    sct.name AS channel_type,
    sc.subscription_id,
    sec.email,
    swc.webhook_url,
    swc.signing_secret
FROM notification_delivery nd
JOIN notification_status ns ON ns.id = nd.status_id
JOIN subscription_channel sc ON sc.id = nd.channel_id
JOIN subscription_channel_type sct ON sct.id = sc.type_id
JOIN notification n ON n.id = nd.notification_id
JOIN notification_type nt ON nt.id = n.type_id
LEFT JOIN subscription_email_channel sec ON sec.id = sc.id
LEFT JOIN subscription_webhook_channel swc ON swc.id = sc.id;

-- Recreate the update trigger
CREATE TRIGGER notification_delivery_update_tg 
INSTEAD OF UPDATE ON v_notification
FOR EACH ROW EXECUTE PROCEDURE notification_delivery_update();