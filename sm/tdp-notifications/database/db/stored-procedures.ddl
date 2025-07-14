--
-- function: check_subscription_exists()
-- description: checks to see if there is a matching subscription for the notification being inserted
-- Note that it makes use of the get_matching_subscriptions() method
--
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
-- function: get_matching_subscriptions
-- description: gets rows from v_subscription_notification that match passed in tenant_id, tenant_customer_id, type_id
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
-- function: subscription_force_initial_status()
-- description: ensures that subscription start with active
--

CREATE OR REPLACE FUNCTION subscription_force_initial_status() RETURNS TRIGGER AS $$
BEGIN

  NEW.status_id = tc_id_from_name('subscription_status','active');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- function: notification_delivery_force_initial_status()
-- description: ensures that notification start with received
--

CREATE OR REPLACE FUNCTION notification_delivery_force_initial_status() RETURNS TRIGGER AS $$
BEGIN

    NEW.status_id = tc_id_from_name('notification_status','received');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- function: set_subscription_channel_type()
-- description: sets subscription_channel_type base on child table name
--

CREATE OR REPLACE FUNCTION set_subscription_channel_type() RETURNS TRIGGER AS $$
BEGIN
  IF TG_TABLE_NAME = 'subscription_poll_channel' THEN
    NEW.type_id = tc_id_from_name('subscription_channel_type', 'poll');
  ELSIF TG_TABLE_NAME = 'subscription_email_channel' THEN
    NEW.type_id = tc_id_from_name('subscription_channel_type', 'email');
  ELSIF TG_TABLE_NAME = 'subscription_webhook_channel' THEN
    NEW.type_id = tc_id_from_name('subscription_channel_type', 'webhook');
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--
-- function: verify_poll_channel_tenant_specific()
-- description: checks that poll channel is for tenant wide subscription
--

CREATE OR REPLACE FUNCTION verify_poll_channel_tenant_specific() RETURNS TRIGGER AS $$
BEGIN
  PERFORM TRUE FROM subscription
  WHERE id = NEW.subscription_id AND tenant_customer_id IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'poll channel is allowed only for tenant subscriptions';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--
-- function: notification_create_deliveries()
-- description: creates notification delivery record for notification per every subscription channel
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
-- function: notification_delivery_update()
-- description: called instead of update on v_notification view
--

CREATE OR REPLACE FUNCTION notification_delivery_update() RETURNS TRIGGER AS $$
BEGIN

  UPDATE notification_delivery SET
    status_id = tc_id_from_name('notification_status', NEW.status),
    status_reason = NEW.status_reason
  WHERE
    id = NEW.id;

  RETURN NEW;
END
$$ LANGUAGE plpgsql;


--
-- function: subscription_update()
-- description: called instead of update on v_subscription view
--

CREATE OR REPLACE FUNCTION subscription_update() RETURNS TRIGGER AS $$
BEGIN

  UPDATE subscription SET
    status_id = tc_id_from_name('subscription_status', NEW.status),
    notification_email = NEW.notification_email,
    descr = NEW.description,
    tags = NEW.tags,
    metadata = NEW.metadata,
    deleted_date = NEW.deleted_date
  WHERE
    id = NEW.id;

  RETURN NEW;
END
$$ LANGUAGE plpgsql;