# History Module

The History Module is designed to maintain historical records of various entities in the system. It provides functionality to track changes, store historical data, and retrieve historical records for auditing and analysis purposes.

## Table of Contents

- [Overview](#overview)
- [Tables](#tables)
- [Functions](#functions)
- [Usage](#usage)
- [Examples](#examples)
- [Contributing](#contributing)
- [License](#license)

## Overview

The History Module consists of several tables and functions that work together to store and manage historical data. The primary purpose of this module is to ensure that changes to important entities are tracked and can be audited or analyzed later. The information is stored for short period of time to be eleted after the expiration date.

## Tables

The following tables are part of the History Module:

- `history.domain`: Stores historical records of domains.
- `history.contact`: Stores historical records of contacts.
- `history.host`: Stores historical records of hosts.
- `history.contact_attribute`: Stores historical records of contact attributes.
- `history.secdns_key_data`: Stores historical records of secDNS key data.
- `history.secdns_ds_data`: Stores historical records of secDNS DS data.
- `history.domain_secdns`: Stores historical records of domain secDNS data.
- `history.domain_contact`: Stores historical records of domain contacts.
- `history.contact_postal`: Stores historical records of contact postal addresses.
- `history.domain_host`: Stores historical records of domain hosts.
- `history.host_addr`: Stores historical records of host addresses.

### Table Definitions

#### `history.domain`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `reason`              | TEXT        | Reason for the historical record   |
| `id`                  | UUID        | Primary key of the domain          |
| `tenant_customer_id`  | UUID        | Tenant customer ID                 |
| `tenant_name`         | TEXT        | Name of the tenant                 |
| `customer_name`       | TEXT        | Name of the customer               |
| `accreditation_tld_id`| UUID        | Accreditation TLD ID               |
| `name`                | FQDN        | Fully Qualified Domain Name        |
| `auth_info`           | TEXT        | Authorization information          |
| `roid`                | TEXT        | Repository Object Identifier       |
| `ry_created_date`     | TIMESTAMPTZ | Registry creation date             |
| `ry_expiry_date`      | TIMESTAMPTZ | Registry expiry date               |
| `ry_updated_date`     | TIMESTAMPTZ | Registry updated date              |
| `ry_transfered_date`  | TIMESTAMPTZ | Registry transferred date          |
| `deleted_date`        | TIMESTAMPTZ | Deletion date                      |
| `expiry_date`         | TIMESTAMPTZ | Expiry date                        |
| `auto_renew`          | BOOLEAN     | Auto-renewal status                |
| `secdns_max_sig_life` | INT         | Maximum signature life for secDNS  |
| `tags`                | TEXT[]      | Tags associated with the domain    |
| `metadata`            | JSONB       | Metadata associated with the domain|
| `uname`               | TEXT        | Username                           |
| `language`            | TEXT        | Language                           |
| `migration_info`      | JSONB       | Migration information              |
| `created_date`        | TIMESTAMPTZ | Creation date (default: NOW())     |

#### `history.contact`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the contact         |
| `orig_id`             | UUID        | Original ID of the contact         |
| `type_id`             | UUID        | Type ID of the contact             |
| `title`               | TEXT        | Title of the contact               |
| `org_reg`             | TEXT        | Organization registration          |
| `org_vat`             | TEXT        | Organization VAT number            |
| `org_duns`            | TEXT        | Organization DUNS number           |
| `tenant_customer_id`  | UUID        | Tenant customer ID                 |
| `email`               | Mbox        | Email address of the contact       |
| `phone`               | TEXT        | Phone number of the contact        |
| `fax`                 | TEXT        | Fax number of the contact          |
| `country`             | TEXT        | Country of the contact             |
| `language`            | TEXT        | Language of the contact            |
| `tags`                | TEXT[]      | Tags associated with the contact   |
| `documentation`       | TEXT[]      | Documentation related to the contact|
| `short_id`            | TEXT        | Short ID of the contact            |
| `metadata`            | JSONB       | Metadata associated with the contact|
| `migration_info`      | JSONB       | Migration information              |

#### `history.host`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the host            |
| `orig_id`             | UUID        | Original ID of the host            |
| `tenant_customer_id`  | UUID        | Tenant customer ID                 |
| `name`                | TEXT        | Name of the host                   |
| `domain_id`           | UUID        | Parent domain ID                   |
| `tags`                | TEXT[]      | Tags associated with the host      |
| `metadata`            | JSONB       | Metadata associated with the host  |

#### `history.contact_attribute`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the contact attribute|
| `attribute_id`        | UUID        | Attribute ID                       |
| `attribute_type_id`   | UUID        | Attribute type ID                  |
| `contact_id`          | UUID        | ID of the associated contact       |
| `value`               | TEXT        | Value of the attribute             |

#### `history.secdns_key_data`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the secDNS key data |
| `flags`               | INT         | Flags                              |
| `protocol`            | INT         | Protocol                           |
| `algorithm`           | INT         | Algorithm                          |
| `public_key`          | TEXT        | Public key                         |

#### `history.secdns_ds_data`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the secDNS DS data  |
| `key_tag`             | INT         | Key tag                            |
| `algorithm`           | INT         | Algorithm                          |
| `digest_type`         | INT         | Digest type                        |
| `digest`              | TEXT        | Digest                             |
| `key_data_id`         | UUID        | References `history.secdns_key_data`|

#### `history.domain_secdns`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the domain secDNS   |
| `domain_id`           | UUID        | References `history.domain`        |
| `ds_data_id`          | UUID        | References `history.secdns_ds_data`|
| `key_data_id`         | UUID        | References `history.secdns_key_data`|

#### `history.domain_contact`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the domain contact  |
| `domain_id`           | UUID        | References `history.domain`        |
| `contact_id`          | UUID        | References `history.contact`       |
| `domain_contact_type_id` | UUID     | Domain contact type ID             |
| `is_local_presence`   | BOOLEAN     | Indicates if local presence        |
| `is_privacy_proxy`    | BOOLEAN     | Indicates if privacy proxy         |
| `is_private`          | BOOLEAN     | Indicates if private               |
| `handle`              | TEXT        | Handle                             |

#### `history.contact_postal`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the contact postal  |
| `orig_id`             | UUID        | Original ID of the contact postal  |
| `contact_id`          | UUID        | References `history.contact`       |
| `is_international`    | BOOLEAN     | Indicates if international         |
| `first_name`          | TEXT        | First name                         |
| `last_name`           | TEXT        | Last name                          |
| `org_name`            | TEXT        | Organization name                  |
| `address1`            | TEXT        | Address line 1                     |
| `address2`            | TEXT        | Address line 2                     |
| `address3`            | TEXT        | Address line 3                     |
| `city`                | TEXT        | City                               |
| `postal_code`         | TEXT        | Postal code                        |
| `state`               | TEXT        | State                              |

#### `history.domain_host`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the domain host     |
| `domain_id`           | UUID        | References `history.domain`        |
| `host_id`             | UUID        | References `history.host`          |

#### `history.host_addr`

| Column                | Type        | Description                        |
|-----------------------|-------------|------------------------------------|
| `id`                  | UUID        | Primary key of the host address    |
| `host_id`             | UUID        | References `history.host`          |
| `address`             | INET        | IP address                         |

## Functions

The History Module includes several functions to manage historical data. These functions handle the insertion of historical records, retrieval of historical data, and other related operations.

### Function Definitions

#### `delete_domain_with_reason`

Deletes a domain and records the reason for deletion.

```sql
CREATE OR REPLACE FUNCTION delete_domain_with_reason(_domain_id UUID, _reason TEXT)
RETURNS void AS $$
-- Function implementation
$$ LANGUAGE plpgsql;
```
