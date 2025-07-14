-- Poll message types
INSERT INTO poll_message_type (name, descr) VALUES 
    ('transfer', 'Transfer notification'),
    ('renewal', 'Renewal notification'),
    ('pending_action', 'Pending action notification'),
    ('domain_info', 'Domain info notification'),
    ('contact_info', 'Contact info notification'),
    ('host_info', 'Host info notification'),
    ('unspec', 'Unspec notification');

-- Poll Message Statuses
INSERT INTO poll_message_status(name,descr) VALUES
    ('pending','Poll message has been created'),
    ('submitted','Poll message has been submitted'),
    ('processed','Poll message has processed successfully'),
    ('failed','Poll message failed');
