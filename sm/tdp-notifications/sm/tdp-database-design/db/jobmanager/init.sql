-- Job Statuses
INSERT INTO job_status(name,descr,is_final,is_success) VALUES
('created','Job has been created',false,true),
('submitted','Job has been submitted',false,true),
('processing','Job is currently running',false,true),
('completed','Job has completed successfully',true,true),
('failed','Job failed',true,false),
('completed_conditionally','Job has completed conditionally',true,true);

-- Job Types
INSERT INTO job_type(name,descr) VALUES('no_op','Basic transaction for testing purposes');

INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    routing_key
) 
VALUES
(
    'provision_host_create',
    'Provisions a host into the backend',
    'provision_host',
    'provision_status',
    'status_id',
    'WorkerJobHostProvision'
),
(
    'provision_host_update',
    'Updates host in domain specific backend',
    'provision_host_update',
    'provision_status',
    'status_id',
    'WorkerJobHostProvision'
),
(
    'provision_host_delete',
    'Deletes host in domain specific backend',
    'provision_host_delete',
    'provision_status',
    'status_id',
    'WorkerJobHostProvision'
),
(
    'provision_domain_delete_host',
    'Deletes a domain host',
    'provision_domain_delete_host',
    'provision_status',
    'status_id',
    'WorkerJobHostProvision'
),
(
    'provision_contact_create',
    'Provisions a contact into the backend',
    'provision_contact',
    'provision_status',
    'status_id',
    'WorkerJobContactProvision'
),
(
    'provision_contact_delete',
    'delete contact in specific backend',
    'provision_contact_delete',
    'provision_status',
    'status_id',
    'WorkerJobContactProvision'
),
(
    'provision_domain_contact_update',
    'Updates contact in domain specific backend',
    'provision_domain_contact_update',
    'provision_status',
    'status_id',
    'WorkerJobContactProvision'
),
(
    'provision_domain_create',
    'Provisions a domain into the backend',
    'provision_domain',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_renew',
    'Renews a domain into the backend',
    'provision_domain_renew',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_redeem',
    'Redeems a domain',
    'provision_domain_redeem',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_redeem_report',
    'Sends domain redeem report',
    'provision_domain_redeem',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_delete',
    'Deletes a domain from the backend',
    'provision_domain_delete',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_update',
    'Updates a domain in the backend',
    'provision_domain_update',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_transfer_in_request',
    'Submits domain transfer request to the backend',
    'provision_domain_transfer_in_request',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_transfer_in_cancel_request',
    'Submits domain transfer cancel request to the backend',
    'provision_domain_transfer_in_cancel_request',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_transfer_in',
    'Fetches transferred domain data',
    'provision_domain_transfer_in',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_domain_transfer_away',
    'Submits domain transfer away action to the backend',
    'provision_domain_transfer_away',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'provision_hosting_certificate_create',
    'Provisions a new hosting certificate',
    'provision_hosting_certificate_create',
    'provision_status',
    'status_id',
    'WorkerJobHostingProvision'
),
(
    'provision_hosting_create',
    'Provisions a new hosting into the backend',
    'provision_hosting_create',
    'provision_status',
    'status_id',
    'WorkerJobHostingProvision'
),
(
    'provision_hosting_delete',
    'Delete a hosting from the backend',
    'provision_hosting_delete',
    'provision_status',
    'status_id',
    'WorkerJobHostingProvision'
),
(
    'provision_hosting_update',
    'Provisions a hosting update into the backend',
    'provision_hosting_update',
    'provision_status',
    'status_id',
    'WorkerJobHostingProvision'
),
(
    'validate_domain_available',
    'Validates domain available in the backend',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobDomainProvision'
),
(
    'validate_host_available',
    'Validates host available in the backend',
    -- job updates reference (order_item_plan) explicitly
    -- to skip provisioning if host is not available
    NULL,
    NULL,
    'status_id',
    'WorkerJobHostProvision'
),
(
    'validate_domain_transferable',
    'Validates domain is transferable',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobDomainProvision'
),
(
    'validate_domain_premium',
    'Validates domain is premium',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobDomainProvision'
),
(
    'validate_domain_claims',
    'Validates domain in claims period ',
    'order_item_plan',
    'order_item_plan_validation_status',
    'validation_status_id',
    'WorkerJobDomainProvision'
)
;

INSERT INTO job_type(
    name,
    descr,
    reference_table,
    reference_status_table,
    reference_status_column,
    is_noop
) 
VALUES
(
    'provision_contact_update',
    'Groups updates for contact in backends',
    'provision_contact_update',
    'provision_status',
    'status_id',
    TRUE
),
(
    'provision_contact_delete_group',
    'Groups delete for contact in backends',
    'provision_contact_delete',
    'provision_status',
    'status_id',
    TRUE
);

INSERT INTO job_type(
    name,
    descr,
    reference_status_table,
    reference_status_column,
    routing_key
) VALUES 
(
    'provision_hosting_dns_check',
    'Check if a user has configured DNS for a hosting request',
    'provision_status',
    'status_id',
    'WorkerJobHostingProvision'
),
(
    'setup_domain_renew',
    'Sets up domain renew job',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
),
(
    'setup_domain_delete',
    'Sets up domain delete job',
    'provision_status',
    'status_id',
    'WorkerJobDomainProvision'
);

