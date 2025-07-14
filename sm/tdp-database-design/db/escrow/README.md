# Escrow Tables Documentation

This document contains the schema and examples for the **Escrow System** database tables, including configuration, statuses, and escrow records.

## Common Escrow Deposit Methods

A table summarizing common methods used for escrow deposits, their descriptions, and the available authentication options:

| Method                                | Description                                      | Authentication Options     | Notes                                                                |
| ------------------------------------- | ------------------------------------------------ | -------------------------- | -------------------------------------------------------------------- |
| **SFTP (SSH File Transfer Protocol)** | Secure file transfer over SSH.                   | Username/password, SSH key | Widely used; supports automation; requires SFTP client.              |
| **FTPS (FTP Secure)**                 | FTP with TLS encryption.                         | Username/password          | Less common; may face firewall issues; requires FTPS client.         |
| **HTTPS Upload**                      | Web-based file upload via secure HTTPS.          | Username/password          | User-friendly; suitable for smaller files; browser-based.            |
| **SCP (Secure Copy Protocol)**        | Command-line file transfer over SSH.             | Username/password, SSH key | Ideal for automation; requires command-line access.                  |
| **Managed File Transfer (MFT)**       | Enterprise-grade secure file transfer solutions. | Varies (e.g., SSO, tokens) | Offers automation, tracking, and compliance features; may be costly. |
| **Encrypted Online Deposit (EOD)**    | Web portal that encrypts files upon upload.      | Username/password          | Simplifies deposit process; ensures encryption; user-friendly.       |

---

## Database Tables

### Escrow Data Tables

Each tenant have escrow data table. It is flat table to hold the whole escrow data. For example Enom data consist of domain name, expiry, nameservers and all fields for all contact types. Every field in that fetched escrow file (`.csv`) will be a column in table. Table name format is `escrow_data_[tenant_name]`.

#### Example: `escrow_data_enom` Table

#### Schema

| Column Name        | Type          | Description                      |
| ------------------ | ------------- | -------------------------------- |
| `id`               | `UUID`        | Primary key                      |
| `domain_name`      | `TEXT`        | Domain name                      |
| `expiry_date`      | `TIMESTAMPTZ` | Expiration date for the domain   |
| `nameservers`      | `TEXT[]`      | List of domain nameservers       |
| `rt_first_name`    | `TEXT`        | Registrant first name            |
| `rt_last_name`     | `TEXT`        | Registrant last name             |
| `rt_address1`      | `TEXT`        | Registrant address line 1        |
| `rt_address2`      | `TEXT`        | Registrant address line 2        |
| `rt_address3`      | `TEXT`        | Registrant address line 3        |
| `rt_city`          | `TEXT`        | Registrant city                  |
| `rt_state`         | `TEXT`        | Registrant state/province        |
| `rt_postal_code`   | `TEXT`        | Registrant postal code           |
| `rt_country_code`  | `TEXT`        | Registrant country code          |
| `rt_email_address` | `TEXT`        | Registrant email address         |
| `rt_phone_number`  | `TEXT`        | Registrant phone number          |
| `rt_fax_number`    | `TEXT`        | Registrant fax number            |
| `ac_first_name`    | `TEXT`        | Admin contact first name         |
| `ac_last_name`     | `TEXT`        | Admin contact last name          |
| `ac_address1`      | `TEXT`        | Admin contact address line 1     |
| `ac_address2`      | `TEXT`        | Admin contact address line 2     |
| `ac_address3`      | `TEXT`        | Admin contact address line 3     |
| `ac_city`          | `TEXT`        | Admin contact city               |
| `ac_state`         | `TEXT`        | Admin contact state/province     |
| `ac_postal_code`   | `TEXT`        | Admin contact postal code        |
| `ac_country_code`  | `TEXT`        | Admin contact country code       |
| `ac_email_address` | `TEXT`        | Admin contact email address      |
| `ac_phone_number`  | `TEXT`        | Admin contact phone number       |
| `ac_fax_number`    | `TEXT`        | Admin contact fax number         |
| `bc_first_name`    | `TEXT`        | Billing contact first name       |
| `bc_last_name`     | `TEXT`        | Billing contact last name        |
| `bc_address1`      | `TEXT`        | Billing contact address line 1   |
| `bc_address2`      | `TEXT`        | Billing contact address line 2   |
| `bc_address3`      | `TEXT`        | Billing contact address line 3   |
| `bc_city`          | `TEXT`        | Billing contact city             |
| `bc_state`         | `TEXT`        | Billing contact state/province   |
| `bc_postal_code`   | `TEXT`        | Billing contact postal code      |
| `bc_country_code`  | `TEXT`        | Billing contact country code     |
| `bc_email_address` | `TEXT`        | Billing contact email address    |
| `bc_phone_number`  | `TEXT`        | Billing contact phone number     |
| `bc_fax_number`    | `TEXT`        | Billing contact fax number       |
| `tc_first_name`    | `TEXT`        | Technical contact first name     |
| `tc_last_name`     | `TEXT`        | Technical contact last name      |
| `tc_address1`      | `TEXT`        | Technical contact address line 1 |
| `tc_address2`      | `TEXT`        | Technical contact address line 2 |
| `tc_address3`      | `TEXT`        | Technical contact address line 3 |
| `tc_city`          | `TEXT`        | Technical contact city           |
| `tc_state`         | `TEXT`        | Technical contact state/province |
| `tc_postal_code`   | `TEXT`        | Technical contact postal code    |
| `tc_country_code`  | `TEXT`        | Technical contact country code   |
| `tc_email_address` | `TEXT`        | Technical contact email address  |
| `tc_phone_number`  | `TEXT`        | Technical contact phone number   |
| `tc_fax_number`    | `TEXT`        | Technical contact fax number     |

#### SQL Definition

```sql
CREATE TABLE escrow_data_enom (
    id                UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    domain_name       TEXT NOT NULL,                                      
    expiry_date       TIMESTAMPTZ,                                        
    nameservers       TEXT[],                                             
    rt_first_name     TEXT,                                               
    rt_last_name      TEXT,                                               
    rt_address1       TEXT,                                               
    rt_address2       TEXT,                                               
    rt_address3       TEXT,                                               
    rt_city           TEXT,                                               
    rt_state          TEXT,                                               
    rt_postal_code    TEXT,                                               
    rt_country_code   TEXT,                                               
    rt_email_address  TEXT,                                               
    rt_phone_number   TEXT,                                               
    rt_fax_number     TEXT,                                               
    ac_first_name     TEXT,                                               
    ac_last_name      TEXT,                                               
    ac_address1       TEXT,                                               
    ac_address2       TEXT,                                               
    ac_address3       TEXT,                                               
    ac_city           TEXT,                                               
    ac_state          TEXT,                                               
    ac_postal_code    TEXT,                                               
    ac_country_code   TEXT,                                               
    ac_email_address  TEXT,                                               
    ac_phone_number   TEXT,                                               
    ac_fax_number     TEXT,                                               
    bc_first_name     TEXT,                                               
    bc_last_name      TEXT,                                               
    bc_address1       TEXT,                                               
    bc_address2       TEXT,                                               
    bc_address3       TEXT,                                               
    bc_city           TEXT,                                               
    bc_state          TEXT,                                               
    bc_postal_code    TEXT,                                               
    bc_country_code   TEXT,                                               
    bc_email_address  TEXT,                                               
    bc_phone_number   TEXT,                                               
    bc_fax_number     TEXT,                                               
    tc_first_name     TEXT,                                               
    tc_last_name      TEXT,                                               
    tc_address1       TEXT,                                               
    tc_address2       TEXT,                                               
    tc_address3       TEXT,                                               
    tc_city           TEXT,                                               
    tc_state          TEXT,                                               
    tc_postal_code    TEXT,                                               
    tc_country_code   TEXT,                                               
    tc_email_address  TEXT,                                               
    tc_phone_number   TEXT,                                               
    tc_fax_number     TEXT                                                
) INHERITS (class.audit_trail);
```

### `escrow_config` Table

This table defines how each tenant delivers data to the escrow provider. It supports multiple deposit methods (e.g. SFTP, HTTPS), authentication types (password, SSH key, token), and encryption formats (e.g. GPG, AES).

#### Schema

| Column Name                | Type                               | Required | Description                                                           |
| -------------------------- | ---------------------------------- | -------- | --------------------------------------------------------------------- |
| `id`                       | `UUID`                             | ✅       | Primary key                                                           |
| `tenant_id`                | `UUID`                             | ✅       | Foreign key to the `tenant` table                                     |
| `iana_id`                  | `TEXT`                             | ✅       | IANA-assigned registry ID                                             |
| `deposit_method`           | `TEXT`                             | ✅       | Method used: `SFTP`, `FTPS`, `HTTPS`, `MFT`, `EOD`. Default is `SFTP` |
| `host`                     | `TEXT`                             | ✅       | Target server/URL to send escrow files                                |
| `port`                     | `INTEGER`                          | ❌       | Optional port number (e.g., `22` for SFTP)                            |
| `path`                     | `TEXT`                             | ❌       | Optional path for protocols like HTTPS                                |
| `username`                 | `TEXT`                             | ❌       | Used for authentication                                               |
| `authentication_method`    | `TEXT`                             | ✅       | One of: `SSH_KEY`, `PASSWORD`, `TOKEN`. Default is `SSH_KEY`          |
| `encryption_method`        | `TEXT`                             | ✅       | One of: `GPG`, `AES-256`. Default is `GPG`                            |
| `notes`                    | `TEXT`                             | ❌       | Optional description                                                  |
| `created_at`, `updated_at` | inherited from `class.audit_trail` | ✅       | Timestamps for auditing                                               |

#### Constraints

- `UNIQUE (tenant_id)`: Ensures that each escrow platform/tenant is unique.

#### SQL Definition

```sql
CREATE TABLE escrow_config (
  id                    UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id             UUID NOT NULL REFERENCES tenant,
  iana_id               TEXT NOT NULL,
  deposit_method        TEXT NOT NULL DEFAULT 'SFTP',
  host                  TEXT NOT NULL,
  port                  INTEGER,
  path                  TEXT,
  username              TEXT,
  authentication_method TEXT NOT NULL DEFAULT 'SSH_KEY',
  encryption_method     TEXT NOT NULL DEFAULT 'GPG',
  notes                 TEXT,
  UNIQUE (tenant_id)
) INHERITS (class.audit_trail);
```

#### Sample Inserts

##### SFTP with SSH key + GPG encryption (default)

```sql
INSERT INTO escrow_config (
    tenant_id,
    iana_id,
    deposit_method,
    host,
    port,
    authentication_method,
    encryption_method,
    notes
) VALUES (
    '11111111-1111-1111-1111-111111111111',
    '9999',
    'SFTP',
    'sftp://escrow.vendor.com',
    22,
    'SSH_KEY',
    'GPG',
    'Daily escrow delivery to Iron Mountain'
);
```

##### HTTPS with token and GPG encryption (default)

```sql
INSERT INTO escrow_config (
    id,
    tenant_id,
    iana_id,
    deposit_method,
    host,
    port,
    path,
    authentication_method,
    encryption_method,
    notes
) VALUES (
    gen_random_uuid(),
    '22222222-2222-2222-2222-222222222222',
    '1234',
    'HTTPS',
    'escrow-api.vendor.com',
    443,
    '/upload'
    'TOKEN',
    'GPG',
    'Token-based HTTPS upload for registry backups'
);
```

##### FTPS with password authentication and GPG encryption (default)

```sql
INSERT INTO escrow_config (
    id,
    tenant_id,
    iana_id,
    deposit_method,
    host,
    port,
    username,
    authentication_method,
    encryption_method,
    notes
) VALUES (
    gen_random_uuid(),
    '33333333-3333-3333-3333-333333333333',
    '5678',
    'FTPS',
    'ftps://ftp.vendor.com',
    21,
    'ftp_user',
    'PASSWORD',
    'GPG',
    'FTPS upload for financial records'
);
```

##### SCP with SSH key authentication and AES-256 encryption

```sql
INSERT INTO escrow_config (
    id,
    tenant_id,
    iana_id,
    deposit_method,
    host,
    port,
    authentication_method,
    encryption_method,
    notes
) VALUES (
    gen_random_uuid(),
    '44444444-4444-4444-4444-444444444444',
    '5678',
    'SCP',
    'scp://escrow.vendor.com',
    22,
    'SSH_KEY',
    'AES-256',
    'SCP file transfer with AES encryption for sensitive data'
);
```

##### Managed File Transfer (MFT) with token and GPG encryption (default)

```sql
INSERT INTO escrow_config (
    id,
    tenant_id,
    iana_id,
    deposit_method,
    host,
    port,
    path,
    authentication_method,
    encryption_method,
    notes
) VALUES (
    gen_random_uuid(),
    '55555555-5555-5555-5555-555555555555',
    '9999',
    'MFT',
    'mft.vendor.com',
    443,
    '/upload',
    'TOKEN',
    'GPG',
    'Managed file transfer with enhanced security and encryption'
);
```

##### Encrypted Online Deposit (EOD) with password authentication and GPG encryption (default)

```sql
INSERT INTO escrow_config (
    id,
    tenant_id,
    iana_id,
    deposit_method,
    host,
    port,
    path,
    username,
    authentication_method,
    encryption_method,
    notes
) VALUES (
    gen_random_uuid(),
    '66666666-6666-6666-6666-666666666666',
    '9876',
    'EOD',
    'deposit.vendor.com',
    443,
    '/upload',
    'eod_user',
    'PASSWORD',
    'GPG',
    'Encrypted online deposit via secure web portal'
);
```

### `escrow_status` Table

This table defines the possible statuses for escrow records, indicating whether the status represents a successful or final state.

#### Schema

| Column Name  | Type      | Required | Description                                 |
| ------------ | --------- | -------- | ------------------------------------------- |
| `id`         | `UUID`    | ✅       | Primary key                                 |
| `name`       | `TEXT`    | ✅       | Unique name of the status                   |
| `descr`      | `TEXT`    | ❌       | Optional description of the status          |
| `is_success` | `BOOLEAN` | ✅       | Indicates if the status represents success  |
| `is_final`   | `BOOLEAN` | ✅       | Indicates if the status is a terminal state |

#### Constraints

- `UNIQUE (name)`: Ensures that each status name is unique.

#### SQL Definition

```sql
CREATE TABLE escrow_status (
    id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL,
    descr       TEXT,
    is_success  BOOLEAN NOT NULL,
    is_final    BOOLEAN NOT NULL,
    UNIQUE (name)
);
```

### `escrow_step` Table

This table stores the steps in the escrow workflow, providing a unique identifier and description for each step.

#### Schema

| Column Name | Type   | Required | Description                      |
| ----------- | ------ | -------- | -------------------------------- |
| `id`        | `UUID` | ✅       | Primary key                      |
| `name`      | `TEXT` | ✅       | Unique name of the workflow step |
| `descr`     | `TEXT` | ❌       | Optional description of the step |

#### Constraints

- `UNIQUE (name)`: Ensures that each workflow step name is unique.

#### SQL Definition

```sql
CREATE TABLE escrow_step (
    id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name        TEXT NOT NULL,
    descr       TEXT,
    UNIQUE (name)
);
```

### `escrow` Table

This table stores the escrow records, linking them to the `escrow_config` table and tracking their current status.

#### Schema

| Column Name                | Type                               | Required | Description                                                             |
| -------------------------- | ---------------------------------- | -------- | ----------------------------------------------------------------------- |
| `id`                       | `UUID`                             | ✅       | Primary key                                                             |
| `config_id`                | `UUID`                             | ✅       | Foreign key referencing the `escrow_config` table                       |
| `start_date`               | `TIMESTAMPTZ`                      | ❌       | Timestamp indicating when the escrow process was started                |
| `end_date`                 | `TIMESTAMPTZ`                      | ❌       | Timestamp indicating when the escrow process was ended                  |
| `status_id`                | `UUID`                             | ✅       | Foreign key referencing the `escrow_status` table; default is `pending` |
| `step`                     | `UUID`                             | ❌       | Foreign key referencing the `escrow_step` table                         |
| `metadata`                 | `JSONB`                            | ❌       | JSON data containing additional metadata; defaults to an empty JSON     |
| `created_at`, `updated_at` | inherited from `class.audit_trail` | ✅       | Timestamps for auditing                                                 |

#### SQL Definition

```sql
CREATE TABLE escrow (
    id                UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    config_id         UUID NOT NULL REFERENCES escrow_config,
    start_date        TIMESTAMPTZ DEFAULT NOW(),
    end_date          TIMESTAMPTZ,
    status_id         UUID NOT NULL DEFAULT tc_id_from_name('escrow_status', 'pending')
                      REFERENCES escrow_status,
    step_id           UUID REFERENCES escrow_step,
    metadata          JSONB DEFAULT '{}'::JSONB
) INHERITS (class.audit_trail);
```
