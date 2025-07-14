use utf8;
package DesignDB::Schema::Result::VOrderProductType;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VOrderProductType

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

=head1 TABLE: C<v_order_product_type>

=cut 

__PACKAGE__->table("v_order_product_type");
__PACKAGE__->result_source_instance->view_definition(" SELECT p.id AS product_id,\n    p.name AS product_name,\n    t.id AS type_id,\n    t.name AS type_name,\n    format('order_item_%s_%s'::text, t.name, p.name) AS rel_name\n   FROM (product p\n     JOIN order_type t ON ((t.product_id = p.id)))\n  ORDER BY p.name, t.name");

=head1 ACCESSORS

=head2 product_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 product_name

  data_type: 'text'
  is_nullable: 1

=head2 type_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 type_name

  data_type: 'text'
  is_nullable: 1

=head2 rel_name

  data_type: 'text'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "product_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "product_name",
  { data_type => "text", is_nullable => 1 },
  "type_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "type_name",
  { data_type => "text", is_nullable => 1 },
  "rel_name",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:xgWFE6L+ABc2BmA55ZKKdA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
