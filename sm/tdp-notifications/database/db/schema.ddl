--
-- table: subscription_status
-- description: this table list the possible statuses of substribtions
--

CREATE TABLE subscription_status (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL,
    descr   TEXT
);

COMMENT ON TABLE subscription_status IS 'List of possible status values for a subscription.';

--
-- table: subscription
-- description: this table list all suibscriptions
--

CREATE TABLE subscription (
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    descr               TEXT,
    status_id           UUID NOT NULL REFERENCES subscription_status,
    tenant_id           UUID NOT NULL,
    tenant_customer_id  UUID,
    notification_email  Mbox NOT NULL,
    metadata            JSONB DEFAULT '{}',
    tags                TEXT[]
) INHERITS (class.audit_trail,class.soft_delete);

COMMENT ON TABLE subscription IS 'Stores subscription data for a customer.';

--
-- table: subscription_channel_type
-- description: this table list possible types for a subscription channel
--

CREATE TABLE subscription_channel_type (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL,
    descr   TEXT
);

COMMENT ON TABLE subscription_channel_type IS 'List of possible types for a subscription channel';

--
-- table: subscription_channel
-- description: this table list all notification channel details 
--

CREATE TABLE subscription_channel (
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    type_id         UUID NOT NULL REFERENCES subscription_channel_type,
    subscription_id UUID NOT NULL REFERENCES subscription ON DELETE CASCADE
) INHERITS (class.audit_trail,class.soft_delete);

COMMENT ON TABLE subscription_channel IS 'Stores subscription channel details';

--
-- table: subscription_poll_channel
-- description: this table list all notification poll channel details 
--

CREATE TABLE subscription_poll_channel (
    PRIMARY KEY(id)
) INHERITS (subscription_channel);

COMMENT ON TABLE subscription_channel IS 'Stores subscription poll channel details';

--
-- table: subscription_email_channel
-- description: this table list all notification email channel details 
--

CREATE TABLE subscription_email_channel (
    PRIMARY KEY(id)
) INHERITS (subscription_channel);

COMMENT ON TABLE subscription_channel IS 'Stores subscription email channel details';

--
-- table: subscription_webhook_channel
-- description: this table list all notification webhook channel details 
--

CREATE TABLE subscription_webhook_channel (
    webhook_url     TEXT NOT NULL,
    signing_secret  TEXT NOT NULL,
    PRIMARY KEY(id)
) INHERITS (subscription_channel);

COMMENT ON TABLE subscription_channel IS 'Stores subscription webhook channel details';

--
-- table: notification_status
-- description: this table list the possible statuses of notifications
--

CREATE TABLE notification_status (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL,
    descr   TEXT
);

COMMENT ON TABLE notification_status IS 'List of possible status values for a notification.';

--
-- table: notification_type
-- description: this table list the possible types of notifications
--

CREATE TABLE notification_type (
    id      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name    TEXT NOT NULL,
    descr   TEXT
);

COMMENT ON TABLE notification_type IS 'List of notification types supported.';

--
-- table: notification
-- description: this table list all notifications
--

CREATE TABLE notification (
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    type_id             UUID NOT NULL REFERENCES notification_type,
    payload             JSONB NOT NULL,
    tenant_id           UUID NOT NULL,
    tenant_customer_id  UUID
) INHERITS (class.audit_trail,class.soft_delete);

COMMENT ON TABLE notification IS 'Stores notification for a subscription.';

--
-- table: subscription_notification_type
-- description: this table maps subscriptions to notification types
--

CREATE TABLE subscription_notification_type (
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    subscription_id UUID NOT NULL REFERENCES subscription ON DELETE CASCADE,
    type_id         UUID NOT NULL REFERENCES notification_type,
    UNIQUE(subscription_id, type_id)
);

COMMENT ON TABLE subscription_notification_type IS 'Stores notification types enabled for a subscription';

--
-- table: notification_delivery
-- description: this table list all notification deliveries
--

CREATE TABLE notification_delivery (
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    notification_id UUID NOT NULL REFERENCES notification ON DELETE CASCADE,
    channel_id      UUID NOT NULL,
    status_id       UUID NOT NULL REFERENCES notification_status,
    status_reason   TEXT NULL,
    retries         INTEGER NOT NULL DEFAULT 3,
    CHECK ( retries >= 0 )
) INHERITS (class.audit_trail,class.soft_delete);

COMMENT ON TABLE notification_delivery IS 'Stores notification delivery details';

--
-- Manage schema migrations.
--
CREATE TABLE IF NOT EXISTS migration (
     version             TEXT PRIMARY KEY,
     name                TEXT NOT NULL,
     applied_date        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
     version_number      TEXT NOT NULL,
     CONSTRAINT valid_version_format CHECK (version_number ~ '^v[0-9]+\.[0-9]+\.[0-9]+$')
);

COMMENT ON TABLE migration IS '
Record of schema migrations applied.
';

COMMENT ON COLUMN migration.version      IS 'Timestamp string of migration file in format YYYYMMDDHHMM (must match filename).';
COMMENT ON COLUMN migration.name         IS 'Name of migration from migration filename.';
COMMENT ON COLUMN migration.applied_date IS 'Postgres timestamp when migration was recorded.';
