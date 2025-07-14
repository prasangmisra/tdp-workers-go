-- data to be used for testing purposes

WITH sub AS (
  INSERT INTO subscription(
    descr,
    notification_email,
    tenant_id,
    tenant_customer_id
  ) VALUES (
    'Test OpenSRS subscription',
    'opensrs@tucows.net',
    '26ac88c7-b774-4f56-938b-9f7378cb3eca',
    NULL
  ) RETURNING id
), channel AS (
    INSERT INTO subscription_poll_channel(
        subscription_id
    ) VALUES (
        (select id from sub)
    )
)
INSERT INTO subscription_notification_type(
    subscription_id,
    type_id
) VALUES
    ((select id from sub), tc_id_from_name('notification_type', 'domain.transfer'));


WITH poll_sub AS (
  INSERT INTO subscription(
    descr,
    notification_email,
    tenant_id,
    tenant_customer_id
  ) VALUES (
    'Test Enom Poll subscription',
    'enom@tucows.net',
    'dc9cb205-e858-4421-bf2c-6e5ebe90991e',
    NULL
  ) RETURNING id
), poll_channel AS (
    INSERT INTO subscription_poll_channel(
        subscription_id
    ) VALUES (
        (select id from poll_sub)
    )
)
INSERT INTO subscription_notification_type(
    subscription_id,
    type_id
) VALUES
    ((select id from poll_sub), tc_id_from_name('notification_type', 'domain.transfer'));

WITH email_sub AS (
  INSERT INTO subscription(
    descr,
    notification_email,
    tenant_id,
    tenant_customer_id
  ) VALUES (
    'Test Enom Email subscription',
    'enom@tucows.net',
    'dc9cb205-e858-4421-bf2c-6e5ebe90991e',
    NULL
  ) RETURNING id
), email_channel AS (
    INSERT INTO subscription_email_channel(
        subscription_id
    ) VALUES (
        (select id from email_sub)
    )
)
INSERT INTO subscription_notification_type(
    subscription_id,
    type_id
) VALUES
    ((select id from email_sub), tc_id_from_name('notification_type', 'account.created'));

INSERT INTO notification (
  type_id,
  payload,
  tenant_id,
  tenant_customer_id
) VALUES (
  tc_id_from_name('notification_type', 'account.created'),
  '{"data": {"last_name": "Bar", "first_name": "Foo", "current_date": "2025-04-08T14:02:46-04:00"}, "envelope": {"subject": "Test email notification", "to_address": [{"name": "Gary Ng", "email": "foo_bar@tucowsinc.com"}]}}',
  'dc9cb205-e858-4421-bf2c-6e5ebe90991e',
  NULL
);

-- define template type for account creation notification
INSERT INTO template_type (name, descr) 
    VALUES 
        ('Account Creation Notification', 'Template for email notification when new account created');

-- map account created notification into template type
INSERT INTO notification_template_type (notification_type_id, template_type_id)
  VALUES
    (tc_id_from_name('notification_type', 'account.created'), tc_id_from_name('template_type', 'Account Creation Notification'));

-- create sections for email header and signature
INSERT INTO section (name, type_id, content)
  VALUES
    (
      'tucows_email_header', 
      tc_id_from_name('section_type', 'header'), 
      '<p><strong>From:</strong> Tucows Inc</p>
<p><strong>To:</strong> {{ .first_name }} {{ .last_name }}</p>
<p><strong>Date:</strong> {{ .current_date }}</p>'
    ),
    (
      'tucows_email_body', 
      tc_id_from_name('section_type', 'body'), 
      '<p>Just Reusable Test Body</p>'
    ),
    (
      'tucows_email_footer', 
      tc_id_from_name('section_type', 'footer'), 
      '<p>
<strong>Tucows Inc</strong><br>
📍 123 Business St, New York, NY 10001<br>
📞 <a href="tel:+11234567890">+1 (123) 456-7890</a>
✉️ <a href="mailto:support@yourcompany.com">support@yourcompany.com</a>
🌐 <a href="https://www.yourcompany.com">Website</a>
</p>'
    );

-- create variables for email header section
INSERT INTO section_variable (name, descr, type_id, section_id)
  VALUES
    ('first_name', 'First name of the recipient', tc_id_from_name('variable_type', 'TEXT'), tc_id_from_name('section', 'tucows_email_header')),
    ('last_name', 'Last name of the recipient', tc_id_from_name('variable_type', 'TEXT'), tc_id_from_name('section', 'tucows_email_header')),
    ('current_date', 'Current date', tc_id_from_name('variable_type', 'TEXT'), tc_id_from_name('section', 'tucows_email_header'));

-- create variables for template itself
INSERT INTO template_variable (name, descr, type_id, template_type_id)
  VALUES
    ('account_name', 'Name of the account', tc_id_from_name('variable_type', 'TEXT'), tc_id_from_name('template_type', 'Account Creation Notification')),
    ('account_id', 'ID of the account', tc_id_from_name('variable_type', 'INTEGER'), tc_id_from_name('template_type', 'Account Creation Notification')),
    ('account_status', 'Status of the account', tc_id_from_name('variable_type', 'TEXT'), tc_id_from_name('template_type', 'Account Creation Notification'));

-- create template with reusable sections for account created notification
WITH account_created_template AS (
  INSERT INTO template (subject, type_id, engine_id, status_id, content)
    VALUES
      (
        'Account Created Notification',
        tc_id_from_name('template_type', 'Account Creation Notification'),
        tc_id_from_name('template_engine', 'go-template'),
        tc_id_from_name('template_status', 'published'),
        '<p>Dear {{ .account_name }},</p>
<p>Your account has been successfully created. Your account ID is {{ .account_id }} and the current status is {{ .account_status }}.</p>
<p>Thank you for choosing Tucows Inc.</p>'
      )
    RETURNING id
)
INSERT INTO template_section (template_id, section_id, position)
  VALUES
    (
      (SELECT id FROM account_created_template),
      tc_id_from_name('section', 'tucows_email_header'),
      1
    ),
    (
      (SELECT id FROM account_created_template),
      tc_id_from_name('section', 'tucows_email_body'),
      1
    ),
    (
      (SELECT id FROM account_created_template),
      tc_id_from_name('section', 'tucows_email_footer'),
      1
    );

