use utf8;
package DesignDB::Schema::Result::OrderItemPlan;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::OrderItemPlan - stores the plan on how an order must be provisioned

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

=head1 TABLE: C<order_item_plan>

=cut 

__PACKAGE__->table("order_item_plan");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 order_item_id

  data_type: 'uuid'
  is_nullable: 0
  size: 16

=head2 parent_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 1
  size: 16

=head2 status_id

  data_type: 'uuid'
  default_value: tc_id_from_name('order_item_plan_status'::text, 'new'::text)
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 order_item_object_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 reference_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

since a foreign key would depend on the `order_item_object_id` type, to simplify the setup 
the reference_id is used to conditionally point to rows in the `create_domain_*` tables

=head2 result_message

  data_type: 'text'
  is_nullable: 1

=head2 result_data

  data_type: 'jsonb'
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
  { data_type => "uuid", is_nullable => 0, size => 16 },
  "parent_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 1, size => 16 },
  "status_id",
  {
    data_type => "uuid",
    default_value => \"tc_id_from_name('order_item_plan_status'::text, 'new'::text)",
    is_foreign_key => 1,
    is_nullable => 0,
    size => 16,
  },
  "order_item_object_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "reference_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "result_message",
  { data_type => "text", is_nullable => 1 },
  "result_data",
  { data_type => "jsonb", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<order_item_plan_order_item_id_order_item_object_id_key>

=over 4

=item * L</order_item_id>

=item * L</order_item_object_id>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "order_item_plan_order_item_id_order_item_object_id_key",
  ["order_item_id", "order_item_object_id"],
);

=head1 RELATIONS

=head2 order_item_object

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderItemObject>

=cut 

__PACKAGE__->belongs_to(
  "order_item_object",
  "DesignDB::Schema::Result::OrderItemObject",
  { id => "order_item_object_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 order_item_plans

Type: has_many

Related object: L<DesignDB::Schema::Result::OrderItemPlan>

=cut 

__PACKAGE__->has_many(
  "order_item_plans",
  "DesignDB::Schema::Result::OrderItemPlan",
  { "foreign.parent_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 parent

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderItemPlan>

=cut 

__PACKAGE__->belongs_to(
  "parent",
  "DesignDB::Schema::Result::OrderItemPlan",
  { id => "parent_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 status

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderItemPlanStatus>

=cut 

__PACKAGE__->belongs_to(
  "status",
  "DesignDB::Schema::Result::OrderItemPlanStatus",
  { id => "status_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:oVhc5jsGTzO6WSj6TmRSgQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
