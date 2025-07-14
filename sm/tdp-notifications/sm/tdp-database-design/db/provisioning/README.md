- [Provisioning Module](#provisioning-module)
  - [Contribution](#contribution)
  - [Implementation](#implementation)
  - [Triggers](#triggers)
  - [Naming Conventions](#naming-conventions)

# Provisioning Module

## Contribution
### Code distribution
- Stored Procedures (`stored-procedures/`): This directory contains SQL files defining stored procedures used by the provisioning module.
  - `validation/`: Contains only triggers.
  - `pre/`: Contains pre provisioning of jobs.
  - `post/`: Contains post provisioning on success or failure.


## Implementation 

The provisioning system is a way to capture requests that are agnostic of the origin. They can come from the **order** system, or by any other component that wants to perform an action on an object.

Any action that needs to be properly recorded for future evaluation should implement a table that inherits from the `class.provision` table, which includes the following definition:

```sql
CREATE TABLE class.provision (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  accreditation_id        UUID NOT NULL REFERENCES accreditation,
  tenant_customer_id      UUID NOT NULL REFERENCES tenant_customer,
  provisioned_date        TIMESTAMPTZ,
  status_id               UUID NOT NULL DEFAULT tc_id_from_name('provision_status','pending') 
                          REFERENCES provision_status,
  roid                    TEXT,
  job_id                  UUID REFERENCES job,
  order_item_plan_ids     UUID[],
  result_message          TEXT,
  result_data             JSONB
);
```

An example of such implementation is the `provision_domain_create`, that adds the folowing fields:


```sql
CREATE TABLE provision_domain (
  name                    FQDN NOT NULL,
  registration_period     INT NOT NULL DEFAULT 1,
  pw                      TEXT NOT NULL DEFAULT TC_GEN_PASSWORD(16),
  is_complete             BOOLEAN NOT NULL DEFAULT FALSE,
  accreditation_tld_id    UUID NOT NULL REFERENCES accreditation_tld,
  ry_created_date         TIMESTAMPTZ,
  ry_expiry_date          TIMESTAMPTZ,
  PRIMARY KEY(id),
  FOREIGN KEY (tenant_customer_id) REFERENCES tenant_customer
) INHERITS (class.audit_trail,class.provision);
```

## Triggers 

There are a set of triggers that are attached to this tables, which implement the following logic:

1. Validate the content
2. Create the job and pass the relevant data 
3. Complete the provisioning when the job completes successfully
4. Depending on whether the `order_item_plan_ids` column is set, update the `order_item_plan` table to signal success of failure, which will subsequently update the status of the order.

## Naming Conventions

Tables should be named in a way that it is clear and precise what the provisioning is, prefixed by the `provision_` name which will provide a hint that it is part of the *provision* module.

Example of table names are:

* `provision_domain` - provision a domains
* `provision_domain_renew` - renews a domain name
* `provision_domain_transfer` - transfer request
* `provision_domain_restore` - restores a domain name. 
* `provision_ssl` - requests the creation of an SSL certificate
* etc.

