use utf8;
package DesignDB::Schema::Result::VProviderInstanceOrderItemStrategy;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VProviderInstanceOrderItemStrategy

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

=head1 TABLE: C<v_provider_instance_order_item_strategy>

=cut 

__PACKAGE__->table("v_provider_instance_order_item_strategy");
__PACKAGE__->result_source_instance->view_definition(" WITH default_strategy AS (\n         SELECT t.id AS type_id,\n            o.id AS object_id,\n            s_1.provision_order\n           FROM ((order_item_strategy s_1\n             JOIN order_item_object o ON ((o.id = s_1.object_id)))\n             JOIN order_type t ON ((t.id = s_1.order_type_id)))\n          WHERE (s_1.provider_instance_id IS NULL)\n        )\n SELECT p.name AS provider_name,\n    p.id AS provider_id,\n    pi.id AS provider_instance_id,\n    pi.name AS provider_instance_name,\n    dob.name AS object_name,\n    dob.id AS object_id,\n    ot.id AS order_type_id,\n    ot.name AS order_type_name,\n    prod.id AS product_id,\n    prod.name AS product_name,\n    COALESCE(s.provision_order, ds.provision_order) AS provision_order,\n        CASE\n            WHEN (s.id IS NULL) THEN true\n            ELSE false\n        END AS is_default\n   FROM ((((((provider_instance pi\n     JOIN default_strategy ds ON (true))\n     JOIN provider p ON ((p.id = pi.provider_id)))\n     JOIN order_item_object dob ON ((dob.id = ds.object_id)))\n     JOIN order_type ot ON ((ds.type_id = ot.id)))\n     JOIN product prod ON ((prod.id = ot.product_id)))\n     LEFT JOIN order_item_strategy s ON (((s.provider_instance_id = pi.id) AND (ot.id = s.order_type_id) AND (s.object_id = dob.id))))\n  ORDER BY p.name, pi.name, dob.name, ot.id");

=head1 ACCESSORS

=head2 provider_name

  data_type: 'text'
  is_nullable: 1

=head2 provider_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_instance_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_instance_name

  data_type: 'text'
  is_nullable: 1

=head2 object_name

  data_type: 'text'
  is_nullable: 1

=head2 object_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_type_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_type_name

  data_type: 'text'
  is_nullable: 1

=head2 product_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 product_name

  data_type: 'text'
  is_nullable: 1

=head2 provision_order

  data_type: 'integer'
  is_nullable: 1

=head2 is_default

  data_type: 'boolean'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "provider_name",
  { data_type => "text", is_nullable => 1 },
  "provider_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_instance_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_instance_name",
  { data_type => "text", is_nullable => 1 },
  "object_name",
  { data_type => "text", is_nullable => 1 },
  "object_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_type_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_type_name",
  { data_type => "text", is_nullable => 1 },
  "product_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "product_name",
  { data_type => "text", is_nullable => 1 },
  "provision_order",
  { data_type => "integer", is_nullable => 1 },
  "is_default",
  { data_type => "boolean", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MX2O303UK+zIfzvNjXssXQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
