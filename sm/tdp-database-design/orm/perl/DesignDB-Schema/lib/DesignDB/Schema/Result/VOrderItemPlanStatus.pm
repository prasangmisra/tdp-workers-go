use utf8;
package DesignDB::Schema::Result::VOrderItemPlanStatus;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VOrderItemPlanStatus

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
__PACKAGE__->table_class("DBIx::Class::ResultSource::View");

=head1 TABLE: C<v_order_item_plan_status>

=cut 

__PACKAGE__->table("v_order_item_plan_status");
__PACKAGE__->result_source_instance->view_definition(" SELECT v_order_item_plan.order_id,\n    v_order_item_plan.order_item_id,\n    v_order_item_plan.depth,\n    count(*) AS total,\n    count(*) FILTER (WHERE (v_order_item_plan.plan_status_name = 'new'::text)) AS total_new,\n    count(*) FILTER (WHERE (v_order_item_plan.plan_status_is_success AND v_order_item_plan.plan_status_is_final)) AS total_success,\n    count(*) FILTER (WHERE ((NOT v_order_item_plan.plan_status_is_success) AND v_order_item_plan.plan_status_is_final)) AS total_fail,\n    count(*) FILTER (WHERE ((NOT v_order_item_plan.plan_status_is_final) AND (v_order_item_plan.plan_status_name <> 'new'::text))) AS total_processing,\n    array_agg(v_order_item_plan.object_name) AS objects,\n    array_agg(v_order_item_plan.object_id) AS object_ids\n   FROM v_order_item_plan\n  GROUP BY v_order_item_plan.order_id, v_order_item_plan.order_item_id, v_order_item_plan.depth\n  ORDER BY v_order_item_plan.depth DESC");

=head1 ACCESSORS

=head2 order_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_item_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 depth

  data_type: 'integer'
  is_nullable: 1

=head2 total

  data_type: 'bigint'
  is_nullable: 1

=head2 total_new

  data_type: 'bigint'
  is_nullable: 1

=head2 total_success

  data_type: 'bigint'
  is_nullable: 1

=head2 total_fail

  data_type: 'bigint'
  is_nullable: 1

=head2 total_processing

  data_type: 'bigint'
  is_nullable: 1

=head2 objects

  data_type: 'text[]'
  is_nullable: 1

=head2 object_ids

  data_type: 'uuid[]'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "order_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_item_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "depth",
  { data_type => "integer", is_nullable => 1 },
  "total",
  { data_type => "bigint", is_nullable => 1 },
  "total_new",
  { data_type => "bigint", is_nullable => 1 },
  "total_success",
  { data_type => "bigint", is_nullable => 1 },
  "total_fail",
  { data_type => "bigint", is_nullable => 1 },
  "total_processing",
  { data_type => "bigint", is_nullable => 1 },
  "objects",
  { data_type => "text[]", is_nullable => 1 },
  "object_ids",
  { data_type => "uuid[]", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:8KOzEwmrRlAumbjSKvG6Aw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
