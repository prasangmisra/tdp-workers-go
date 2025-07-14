use utf8;
package DesignDB::Schema::Result::VOrderItemPlan;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VOrderItemPlan

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

=head1 TABLE: C<v_order_item_plan>

=cut 

__PACKAGE__->table("v_order_item_plan");
__PACKAGE__->result_source_instance->view_definition(" WITH RECURSIVE plan AS NOT MATERIALIZED (\n         SELECT o.id AS order_id,\n            p.id,\n            p.parent_id,\n            t.id AS order_type_id,\n            prod.id AS product_id,\n            p.order_item_id,\n            s.id AS plan_status_id,\n            obj.id AS object_id,\n            prod.name AS product_name,\n            t.name AS order_type_name,\n            s.name AS plan_status_name,\n            s.is_success AS plan_status_is_success,\n            s.is_final AS plan_status_is_final,\n            obj.name AS object_name,\n            p.reference_id,\n            NULL::text AS parent_object_name,\n            0 AS depth\n           FROM ((((((order_item_plan p\n             JOIN order_item_object obj ON ((obj.id = p.order_item_object_id)))\n             JOIN order_item_plan_status s ON ((s.id = p.status_id)))\n             JOIN order_item oi ON ((oi.id = p.order_item_id)))\n             JOIN \"order\" o ON ((o.id = oi.order_id)))\n             JOIN order_type t ON ((t.id = o.type_id)))\n             JOIN product prod ON ((prod.id = t.product_id)))\n          WHERE (p.parent_id IS NULL)\n        UNION\n         SELECT o.id AS order_id,\n            p.id,\n            p.parent_id,\n            t.id AS order_type_id,\n            prod.id AS product_id,\n            p.order_item_id,\n            s.id AS plan_status_id,\n            obj.id AS object_id,\n            prod.name AS product_name,\n            t.name AS order_type_name,\n            s.name AS plan_status_name,\n            s.is_success AS plan_status_is_success,\n            s.is_final AS plan_status_is_final,\n            obj.name AS object_name,\n            p.reference_id,\n            plan_1.object_name AS parent_object_name,\n            (plan_1.depth + 1)\n           FROM (((((((order_item_plan p\n             JOIN order_item_object obj ON ((obj.id = p.order_item_object_id)))\n             JOIN order_item_plan_status s ON ((s.id = p.status_id)))\n             JOIN order_item oi ON ((oi.id = p.order_item_id)))\n             JOIN \"order\" o ON ((o.id = oi.order_id)))\n             JOIN order_type t ON ((t.id = o.type_id)))\n             JOIN product prod ON ((prod.id = t.product_id)))\n             JOIN plan plan_1 ON ((p.parent_id = plan_1.id)))\n        )\n SELECT plan.order_id,\n    plan.id,\n    plan.parent_id,\n    plan.order_type_id,\n    plan.product_id,\n    plan.order_item_id,\n    plan.plan_status_id,\n    plan.object_id,\n    plan.product_name,\n    plan.order_type_name,\n    plan.plan_status_name,\n    plan.plan_status_is_success,\n    plan.plan_status_is_final,\n    plan.object_name,\n    plan.reference_id,\n    plan.parent_object_name,\n    plan.depth\n   FROM plan\n  ORDER BY plan.depth DESC");

=head1 ACCESSORS

=head2 order_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 parent_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_type_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 product_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_item_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 plan_status_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 object_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 product_name

  data_type: 'text'
  is_nullable: 1

=head2 order_type_name

  data_type: 'text'
  is_nullable: 1

=head2 plan_status_name

  data_type: 'text'
  is_nullable: 1

=head2 plan_status_is_success

  data_type: 'boolean'
  is_nullable: 1

=head2 plan_status_is_final

  data_type: 'boolean'
  is_nullable: 1

=head2 object_name

  data_type: 'text'
  is_nullable: 1

=head2 reference_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 parent_object_name

  data_type: 'text'
  is_nullable: 1

=head2 depth

  data_type: 'integer'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "order_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "parent_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_type_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "product_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_item_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "plan_status_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "object_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "product_name",
  { data_type => "text", is_nullable => 1 },
  "order_type_name",
  { data_type => "text", is_nullable => 1 },
  "plan_status_name",
  { data_type => "text", is_nullable => 1 },
  "plan_status_is_success",
  { data_type => "boolean", is_nullable => 1 },
  "plan_status_is_final",
  { data_type => "boolean", is_nullable => 1 },
  "object_name",
  { data_type => "text", is_nullable => 1 },
  "reference_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "parent_object_name",
  { data_type => "text", is_nullable => 1 },
  "depth",
  { data_type => "integer", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gXUx4JIb0ta76wxl8No1Yg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
