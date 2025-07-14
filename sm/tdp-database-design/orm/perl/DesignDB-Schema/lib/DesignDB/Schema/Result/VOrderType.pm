use utf8;
package DesignDB::Schema::Result::VOrderType;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VOrderType

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

=head1 TABLE: C<v_order_type>

=cut 

__PACKAGE__->table("v_order_type");
__PACKAGE__->result_source_instance->view_definition(" SELECT p.id AS product_id,\n    p.name AS product_name,\n    ot.id,\n    ot.name\n   FROM (product p\n     JOIN order_type ot ON ((ot.product_id = p.id)))");

=head1 ACCESSORS

=head2 product_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 product_name

  data_type: 'text'
  is_nullable: 1

=head2 id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 name

  data_type: 'text'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "product_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "product_name",
  { data_type => "text", is_nullable => 1 },
  "id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "name",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wuuggVKwUrITeKGn0TIj/A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
