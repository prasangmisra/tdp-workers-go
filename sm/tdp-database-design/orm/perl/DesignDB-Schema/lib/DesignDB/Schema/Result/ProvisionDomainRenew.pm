use utf8;
package DesignDB::Schema::Result::ProvisionDomainRenew;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::ProvisionDomainRenew

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

=head1 TABLE: C<provision_domain_renew>

=cut 

__PACKAGE__->table("provision_domain_renew");

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

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 accreditation_id

  data_type: 'uuid'
  is_nullable: 0
  size: 16

=head2 tenant_customer_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 provisioned_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 status_id

  data_type: 'uuid'
  default_value: tc_id_from_name('provision_status'::text, 'pending'::text)
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 roid

  data_type: 'text'
  is_nullable: 1

=head2 job_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_item_plan_ids

  data_type: 'uuid[]'
  is_nullable: 1

=head2 result_message

  data_type: 'text'
  is_nullable: 1

=head2 result_data

  data_type: 'jsonb'
  is_nullable: 1

=head2 domain_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 1
  size: 16

=head2 period

  data_type: 'integer'
  default_value: 1
  is_nullable: 0

=head2 current_expiry_date

  data_type: 'timestamp with time zone'
  is_nullable: 0

=head2 is_auto

  data_type: 'boolean'
  default_value: false
  is_nullable: 0

=head2 ry_expiry_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

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
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "accreditation_id",
  { data_type => "uuid", is_nullable => 0, size => 16 },
  "tenant_customer_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "provisioned_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "status_id",
  {
    data_type => "uuid",
    default_value => \"tc_id_from_name('provision_status'::text, 'pending'::text)",
    is_foreign_key => 1,
    is_nullable => 0,
    size => 16,
  },
  "roid",
  { data_type => "text", is_nullable => 1 },
  "job_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_item_plan_ids",
  { data_type => "uuid[]", is_nullable => 1 },
  "result_message",
  { data_type => "text", is_nullable => 1 },
  "result_data",
  { data_type => "jsonb", is_nullable => 1 },
  "domain_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 1, size => 16 },
  "period",
  { data_type => "integer", default_value => 1, is_nullable => 0 },
  "current_expiry_date",
  { data_type => "timestamp with time zone", is_nullable => 0 },
  "is_auto",
  { data_type => "boolean", default_value => \"false", is_nullable => 0 },
  "ry_expiry_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 domain

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Domain>

=cut 

__PACKAGE__->belongs_to(
  "domain",
  "DesignDB::Schema::Result::Domain",
  { id => "domain_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "NO ACTION",
  },
);

=head2 status

Type: belongs_to

Related object: L<DesignDB::Schema::Result::ProvisionStatus>

=cut 

__PACKAGE__->belongs_to(
  "status",
  "DesignDB::Schema::Result::ProvisionStatus",
  { id => "status_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 tenant_customer

Type: belongs_to

Related object: L<DesignDB::Schema::Result::TenantCustomer>

=cut 

__PACKAGE__->belongs_to(
  "tenant_customer",
  "DesignDB::Schema::Result::TenantCustomer",
  { id => "tenant_customer_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ALs9LiN6PebPe9vK2QlHrw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
