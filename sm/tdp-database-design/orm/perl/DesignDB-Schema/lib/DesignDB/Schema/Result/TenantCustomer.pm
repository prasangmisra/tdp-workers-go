use utf8;
package DesignDB::Schema::Result::TenantCustomer;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::TenantCustomer

=cut 

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut 

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<tenant_customer>

=cut 

__PACKAGE__->table("tenant_customer");

=head1 ACCESSORS

=head2 created_date

  data_type: 'timestamp with time zone'
  default_value: current_timestamp
  is_nullable: 1
  original: {default_value => \"now()"}

=head2 updated_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 created_by

  data_type: 'text'
  default_value: CURRENT_USER
  is_nullable: 1

=head2 updated_by

  data_type: 'text'
  is_nullable: 1

=head2 deleted_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 deleted_by

  data_type: 'text'
  is_nullable: 1

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 tenant_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 customer_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 customer_number

  data_type: 'text'
  is_nullable: 0

=cut 

__PACKAGE__->add_columns(
  "created_date",
  {
    data_type     => "timestamp with time zone",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "updated_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "created_by",
  { data_type => "text", default_value => \"CURRENT_USER", is_nullable => 1 },
  "updated_by",
  { data_type => "text", is_nullable => 1 },
  "deleted_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "deleted_by",
  { data_type => "text", is_nullable => 1 },
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "tenant_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "customer_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "customer_number",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<tenant_customer_tenant_id_customer_id_key>

=over 4

=item * L</tenant_id>

=item * L</customer_id>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "tenant_customer_tenant_id_customer_id_key",
  ["tenant_id", "customer_id"],
);

=head2 C<tenant_customer_tenant_id_customer_number_key>

=over 4

=item * L</tenant_id>

=item * L</customer_number>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "tenant_customer_tenant_id_customer_number_key",
  ["tenant_id", "customer_number"],
);

=head1 RELATIONS

=head2 contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::Contact>

=cut 

__PACKAGE__->has_many(
  "contacts",
  "DesignDB::Schema::Result::Contact",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 customer

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Customer>

=cut 

__PACKAGE__->belongs_to(
  "customer",
  "DesignDB::Schema::Result::Customer",
  { id => "customer_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 domains

Type: has_many

Related object: L<DesignDB::Schema::Result::Domain>

=cut 

__PACKAGE__->has_many(
  "domains",
  "DesignDB::Schema::Result::Domain",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 hosts

Type: has_many

Related object: L<DesignDB::Schema::Result::Host>

=cut 

__PACKAGE__->has_many(
  "hosts",
  "DesignDB::Schema::Result::Host",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 jobs

Type: has_many

Related object: L<DesignDB::Schema::Result::Job>

=cut 

__PACKAGE__->has_many(
  "jobs",
  "DesignDB::Schema::Result::Job",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 orders

Type: has_many

Related object: L<DesignDB::Schema::Result::Order>

=cut 

__PACKAGE__->has_many(
  "orders",
  "DesignDB::Schema::Result::Order",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_contacts

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionContact>

=cut 

__PACKAGE__->has_many(
  "provision_contacts",
  "DesignDB::Schema::Result::ProvisionContact",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_domains

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionDomain>

=cut 

__PACKAGE__->has_many(
  "provision_domains",
  "DesignDB::Schema::Result::ProvisionDomain",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_domains_renew

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionDomainRenew>

=cut 

__PACKAGE__->has_many(
  "provision_domains_renew",
  "DesignDB::Schema::Result::ProvisionDomainRenew",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provision_hosts

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionHost>

=cut 

__PACKAGE__->has_many(
  "provision_hosts",
  "DesignDB::Schema::Result::ProvisionHost",
  { "foreign.tenant_customer_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 tenant

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Tenant>

=cut 

__PACKAGE__->belongs_to(
  "tenant",
  "DesignDB::Schema::Result::Tenant",
  { id => "tenant_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/f9bbzMcvr9r4U3l3QuFng


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
