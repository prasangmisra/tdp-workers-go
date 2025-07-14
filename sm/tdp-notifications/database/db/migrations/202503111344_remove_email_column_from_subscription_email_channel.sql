-- Remove the "email" column from the subscription_email_channel table
-- https://wiki-tucows.atlassian.net/browse/DEM-116

-- Drop dependent function before dropping the view
DROP FUNCTION IF EXISTS get_matching_subscriptions(UUID, UUID, UUID);

-- Drop and recreate v_subscription_channel
DROP VIEW IF EXISTS v_subscription_channel;

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

-- Drop and recreate v_notification
DROP VIEW IF EXISTS v_notification CASCADE;

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

CREATE TRIGGER notification_delivery_update_tg
    INSTEAD OF UPDATE ON v_notification
    FOR EACH ROW EXECUTE PROCEDURE notification_delivery_update();

-- Remove the "email" column now that dependencies are cleared
ALTER TABLE IF EXISTS subscription_email_channel
DROP COLUMN IF EXISTS email;

-- Recreate the get_matching_subscriptions function (depends on the recreated view)
CREATE OR REPLACE FUNCTION get_matching_subscriptions(mtenant_id UUID, mtenant_customer_id UUID, mtype_id UUID)
RETURNS SETOF v_subscription_channel AS $$
BEGIN
	RETURN QUERY
	SELECT VSC.*
     FROM v_subscription_channel vsc
     WHERE vsc.tenant_id = mtenant_id AND
        (
          vsc.tenant_customer_id IS NULL AND mtenant_customer_id IS NULL OR
          vsc.tenant_customer_id = mtenant_customer_id
        ) AND
        tc_name_from_id('notification_type', mtype_id) = ANY(vsc.notifications);
END;
$$ LANGUAGE plpgsql;
