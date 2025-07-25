use utf8;
package DesignDB::Schema::Result::Job;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::Job

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

=head1 TABLE: C<job>

=cut 

__PACKAGE__->table("job");

=head1 ACCESSORS

=head2 created_date

  data_type: 'timestamp with time zone'
  default_value: current_timestamp
  is_nullable: 0
  original: {default_value => \"now()"}

=head2 updated_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 created_by

  data_type: 'text'
  default_value: CURRENT_USER
  is_nullable: 0

=head2 updated_by

  data_type: 'text'
  is_nullable: 1

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 tenant_customer_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 1
  size: 16

=head2 type_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 status_id

  data_type: 'uuid'
  default_value: tc_id_from_name('job_status'::text, 'submitted'::text)
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 start_date

  data_type: 'timestamp with time zone'
  default_value: current_timestamp
  is_nullable: 1
  original: {default_value => \"now()"}

=head2 end_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 retry_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 retry_count

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 reference_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 data

  data_type: 'jsonb'
  is_nullable: 1

=head2 result_msg

  data_type: 'text'
  is_nullable: 1

=head2 result_data

  data_type: 'jsonb'
  is_nullable: 1

=head2 event_id

  data_type: 'text'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "created_date",
  {
    data_type     => "timestamp with time zone",
    default_value => \"current_timestamp",
    is_nullable   => 0,
    original      => { default_value => \"now()" },
  },
  "updated_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "created_by",
  { data_type => "text", default_value => \"CURRENT_USER", is_nullable => 0 },
  "updated_by",
  { data_type => "text", is_nullable => 1 },
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "tenant_customer_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 1, size => 16 },
  "type_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "status_id",
  {
    data_type => "uuid",
    default_value => \"tc_id_from_name('job_status'::text, 'submitted'::text)",
    is_foreign_key => 1,
    is_nullable => 0,
    size => 16,
  },
  "start_date",
  {
    data_type     => "timestamp with time zone",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "end_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "retry_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "retry_count",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "reference_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "data",
  { data_type => "jsonb", is_nullable => 1 },
  "result_msg",
  { data_type => "text", is_nullable => 1 },
  "result_data",
  { data_type => "jsonb", is_nullable => 1 },
  "event_id",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 status

Type: belongs_to

Related object: L<DesignDB::Schema::Result::JobStatus>

=cut 

__PACKAGE__->belongs_to(
  "status",
  "DesignDB::Schema::Result::JobStatus",
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
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 type

Type: belongs_to

Related object: L<DesignDB::Schema::Result::JobType>

=cut 

__PACKAGE__->belongs_to(
  "type",
  "DesignDB::Schema::Result::JobType",
  { id => "type_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gqBZIKKorK3gm/7YaJL6SQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
