# Job Chaining

This document describes possible solutions for job chaining. Job chaining is when one job spawns another sub-job. For example, creating or updating a domain and then setting locks. It might also be used to submit a report after a restore operation for domain redeem.

## Proposed solutions

1. Update job table with `parent_id` field
- Description: Add new field `parent_id` to the job schema, allowing a job to reference its parent.

- Implementation:
    - Modify the `job_reference_status_update` function to check if a `parent_id` is set. If so, update the job table accordingly instead of relying on the reference table from `job_type`.

<br>

2. Introduce `reference_table` and `reference_status_table` fields in job schema
- Description: Add new fields, `reference_table` and `reference_status_table`, to the job schema. These fields would override the reference table specified in `job_type`.

- Implementation:
    - Utilize the `reference_table` and `reference_status_table` fields within the `job_reference_status_update` function to provide flexibility in specifying the tables to reference.

<br>

3. Expand `job_type` Entries to Include Direct Job Table References
- Description: Augment the `job_type` entries to directly reference job tables, enabling more direct implementation without any changes.

- Implementation:
    - Duplicate existing job types as needed to reference job tables.
    ```json
            {
                "id" : "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                "name" : "provision_domain_update_child",
                "descr" : "Updates a domain in the backend",
                "reference_table" : "job",
                "reference_status_table" : "job_status",
                "reference_status_column" : "status_id",
                "routing_key" : "WorkerJobDomainProvision"
            }    
    ```

## Preferred Solution and Additional Points
The preferred solution is to update the job table to have parent_id to reference the parent job (solution 1). 

> This solution supports multiple child jobs for job chaining. logic for managing child jobs can be implemented within the `job_reference_status_update` function.

### Handling child job failure
- Jobs Affected by Child Job Failure:
    - Certain parent jobs are directly impacted by the success or failure of their child jobs. If any child fails, the parent is marked as failed
    - Example: In domain redeem order, failure in report processing (second step) results in the entire order being marked as failed.
- Jobs Unaffected by Child Job Failure:
  
  > These jobs are "best effort" ones. How do we notify, detect job failure, or implement the retry mechanism is up to further discussion.
  - In specific scenarios, a child job's failure may not directly influence the outcome of its parent job. In such cases, the parent job continues its execution despite the failure of its child job. These jobs would be created with no parent_id. 
  - Example: During domain creation, if the job of setting EPP statuses fails, the domain creation process itself should not be considered failed, as it can proceed without setting these statuses.
