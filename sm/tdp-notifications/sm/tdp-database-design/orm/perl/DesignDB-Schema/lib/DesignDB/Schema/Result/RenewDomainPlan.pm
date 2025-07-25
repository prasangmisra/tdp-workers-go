use utf8;
package DesignDB::Schema::Result::RenewDomainPlan;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::RenewDomainPlan

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

=head1 TABLE: C<renew_domain_plan>

=cut 

__PACKAGE__->table("renew_domain_plan");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 order_item_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 parent_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 status_id

  data_type: 'uuid'
  default_value: tc_id_from_name('order_item_plan_status'::text, 'new'::text)
  is_nullable: 0
  size: 16

=head2 order_item_object_id

  data_type: 'uuid'
  is_nullable: 0
  size: 16

=head2 reference_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 result_message

  data_type: 'text'
  is_nullable: 1

=head2 result_data

  data_type: 'jsonb'
  is_nullable: 1

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

=cut 

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "order_item_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "parent_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "status_id",
  {
    data_type => "uuid",
    default_value => \"tc_id_from_name('order_item_plan_status'::text, 'new'::text)",
    is_nullable => 0,
    size => 16,
  },
  "order_item_object_id",
  { data_type => "uuid", is_nullable => 0, size => 16 },
  "reference_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "result_message",
  { data_type => "text", is_nullable => 1 },
  "result_data",
  { data_type => "jsonb", is_nullable => 1 },
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
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 order_item

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderItemRenewDomain>

=cut 

__PACKAGE__->belongs_to(
  "order_item",
  "DesignDB::Schema::Result::OrderItemRenewDomain",
  { id => "order_item_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:DSgbzP6SZmVLB6Nk6g+eXA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
