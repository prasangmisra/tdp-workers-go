INSERT INTO subscription_status (name, descr) 
    VALUES 
        ('active', 'Subscription is active'),
        ('paused', 'Subscription is paused'),
        ('degraded', 'Subscription is degraded'),
        ('deactivated', 'Subscription is deactivated');

INSERT INTO notification_status (name, descr) 
    VALUES 
        ('received', 'Notification has been received'),
        ('publishing', 'Notification has being published'),
        ('published', 'Notification published'),
        ('failed', 'Notification failed to be published'),
        ('unsupported', 'Notification is not supported');

INSERT INTO notification_type (name) 
    VALUES 
        ('contact.created'),
        ('contact.updated'),
        ('contact.deleted'),
        ('domain.created'),
        ('domain.renewed'),
        ('domain.expired'),
        ('domain.deleted'),
        ('domain.transfer'),
        ('account.created');

INSERT INTO Subscription_channel_type (name, descr) 
    VALUES 
        ('email', 'Channel for email notifications'),
        ('webhook', 'Channel for webhook notifications'),
        ('poll', 'Channel for EPP poll messages notifications');
