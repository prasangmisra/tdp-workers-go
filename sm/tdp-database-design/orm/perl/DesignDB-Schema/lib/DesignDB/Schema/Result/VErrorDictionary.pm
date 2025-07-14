use utf8;
package DesignDB::Schema::Result::VErrorDictionary;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VErrorDictionary

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

=head1 TABLE: C<v_error_dictionary>

=cut 

__PACKAGE__->table("v_error_dictionary");
__PACKAGE__->result_source_instance->view_definition(" SELECT d.id,\n    c.name AS category,\n    d.message,\n    d.columns_affected\n   FROM (error_dictionary d\n     JOIN error_category c ON ((c.id = d.category_id)))");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_nullable: 1

=head2 category

  data_type: 'text'
  is_nullable: 1

=head2 message

  data_type: 'text'
  is_nullable: 1

=head2 columns_affected

  data_type: 'text[]'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_nullable => 1 },
  "category",
  { data_type => "text", is_nullable => 1 },
  "message",
  { data_type => "text", is_nullable => 1 },
  "columns_affected",
  { data_type => "text[]", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:1gYRI4Go+JZkpeuNMmSyzQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
