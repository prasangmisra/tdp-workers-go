-- Cannot update function untill trigger is removed
DROP TRIGGER delete_notification_if_all_deliveries_published_tg ON notification_delivery;

-- Drop the function
DROP FUNCTION delete_notification_if_all_deliveries_published();