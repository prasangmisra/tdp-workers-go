BEGIN;

-- Modify foreign key constraint to be deferrable
ALTER TABLE notification_delivery
  DROP CONSTRAINT notification_delivery_notification_id_fkey,  -- Remove existing foreign key constraint
  ADD CONSTRAINT notification_delivery_notification_id_fkey    -- Add it back with deferrable settings
  FOREIGN KEY (notification_id)
  REFERENCES notification(id)
  ON DELETE CASCADE
  DEFERRABLE INITIALLY DEFERRED;

-- Add trigger to check and delete notifications if all deliveries are published
CREATE OR REPLACE FUNCTION delete_notification_if_all_deliveries_published() RETURNS TRIGGER AS $$
BEGIN
    -- Set the transaction isolation level to REPEATABLE READ to avoid race conditions
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

    -- Lock the notification row to avoid concurrent updates/deletes
    PERFORM 1 FROM notification WHERE id = NEW.notification_id FOR UPDATE;

    -- Check if there are any unfinished deliveries
    IF NOT EXISTS (
        SELECT 1
        FROM notification_delivery
        WHERE notification_id = NEW.notification_id
        AND status_id != tc_id_from_name('notification_status', 'published')
    ) THEN
        -- If no unfinished deliveries, delete the notification
        DELETE FROM notification WHERE id = NEW.notification_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to call the function on notification_delivery status update
CREATE TRIGGER delete_notification_if_all_deliveries_published_tg
AFTER UPDATE OF status_id ON notification_delivery
FOR EACH ROW
WHEN (OLD.status_id != NEW.status_id AND NEW.status_id = tc_id_from_name('notification_status', 'published'))
EXECUTE PROCEDURE delete_notification_if_all_deliveries_published();

COMMIT;