-- 
-- Several parts to this:
-- 1. Define a function that gets all subscriptions that match a new notification's tenant_id, tenant_customer_id, and type_id
-- 2. Update the existing notification_create_deliveries() method to use this new function 
-- 3. Create a new function that will raise an error if, when attempting to insert a notification row, will raise an error if there is no matching subscriptions
-- 4. Create a new trigger that will call this new function on insert into the notification table
-- 5. On insert into the notification table, ONLY create a notification_delivery entry IF the status of the subscription is 'active'
-- (Source JIRA: https://wiki-tucows.atlassian.net/browse/DEM-114)
--


--
-- PART 1. Define a function that gets all subscriptions that match a new notification's tenant_id, tenant_customer_id, and type_id
-- function: get_matching_subscriptions
-- description: gets rows from v_subscrition_notification that match passed in tenant_id, tenant_customer_id, type_id
--
CREATE OR REPLACE FUNCTION get_matching_subscriptions(mtenant_id UUID, mtenant_customer_id UUID, mtype_id UUID) RETURNS SETOF v_subscription_channel as $$
BEGIN
	RETURN QUERY
	SELECT VSC.*
     FROM v_subscription_channel vsc
     WHERE vsc.tenant_id = mtenant_id AND
        (
          -- notification are matched by tenant id
          -- matching by tenant_customer_id is happening only if provided
          vsc.tenant_customer_id IS NULL AND mtenant_customer_id IS NULL OR
          vsc.tenant_customer_id = mtenant_customer_id
        ) AND
        tc_name_from_id('notification_type', mtype_id) = ANY(vsc.notifications);
END;
$$ LANGUAGE plpgsql;

--
-- PART 2. Update the existing notification_create_deliveries() method to use this new function
--
CREATE OR REPLACE FUNCTION notification_create_deliveries() RETURNS TRIGGER AS $$
DECLARE
   _subscription_channel  RECORD;
BEGIN
  FOR _subscription_channel IN
     SELECT * FROM get_matching_subscriptions(NEW.tenant_id, NEW.tenant_customer_id, NEW.type_id)
   LOOP
     INSERT INTO notification_delivery(
       notification_id,
       channel_id
     ) VALUES (
       NEW.id,
       _subscription_channel.id
     );
   END LOOP;
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- PART 3. Create a new function that will raise an error if, when attempting to insert a notification row, will raise an error if there is no matching subscriptions
-- First, drop existing trigger
--
DROP TRIGGER IF EXISTS notfication_check_subscription_exists_tg ON notification;

-- Now define the function that will check to see if a given subscription exists for a specific type
-- Note that it uses the function we defined above
DROP FUNCTION IF EXISTS check_subscription_exists() ;
CREATE OR REPLACE FUNCTION check_subscription_exists() RETURNS TRIGGER AS $$
DECLARE
  number_of_rows int;
BEGIN
	SELECT COUNT (*) INTO number_of_rows FROM get_matching_subscriptions(NEW.tenant_id, NEW.tenant_customer_id, NEW.type_id);
	if (number_of_rows = 0) THEN
    RAISE EXCEPTION 'No subscription found for the given notification';
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

--
-- PART 4. Create a new trigger that will call this new function on insert into the notification table
--
CREATE TRIGGER notfication_check_subscription_exists_tg BEFORE INSERT ON notification
FOR EACH ROW EXECUTE PROCEDURE check_subscription_exists();

--
-- PART 5. On insert into the notification table, ONLY create a notification_delivery entry IF the status of the subscription is 'active'
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

CREATE TRIGGER notification_delivery_update_tg INSTEAD OF UPDATE ON v_notification
    FOR EACH ROW EXECUTE PROCEDURE notification_delivery_update();