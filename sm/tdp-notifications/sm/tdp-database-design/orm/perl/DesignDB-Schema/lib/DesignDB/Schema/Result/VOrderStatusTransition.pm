use utf8;
package DesignDB::Schema::Result::VOrderStatusTransition;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VOrderStatusTransition

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

=head1 TABLE: C<v_order_status_transition>

=cut 

__PACKAGE__->table("v_order_status_transition");
__PACKAGE__->result_source_instance->view_definition(" SELECT ost.path_id,\n    osp.name AS path_name,\n    f.id AS source_status_id,\n    t.id AS target_status_id,\n    f.name AS from_status,\n    t.name AS to_status,\n    f.is_success AS is_source_success,\n    t.is_success AS is_target_success,\n    t.is_final\n   FROM (((order_status_transition ost\n     JOIN order_status_path osp ON ((osp.id = ost.path_id)))\n     JOIN order_status f ON ((f.id = ost.from_id)))\n     JOIN order_status t ON ((t.id = ost.to_id)))");

=head1 ACCESSORS

=head2 path_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 path_name

  data_type: 'text'
  is_nullable: 1

=head2 source_status_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 target_status_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 from_status

  data_type: 'text'
  is_nullable: 1

=head2 to_status

  data_type: 'text'
  is_nullable: 1

=head2 is_source_success

  data_type: 'boolean'
  is_nullable: 1

=head2 is_target_success

  data_type: 'boolean'
  is_nullable: 1

=head2 is_final

  data_type: 'boolean'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "path_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "path_name",
  { data_type => "text", is_nullable => 1 },
  "source_status_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "target_status_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "from_status",
  { data_type => "text", is_nullable => 1 },
  "to_status",
  { data_type => "text", is_nullable => 1 },
  "is_source_success",
  { data_type => "boolean", is_nullable => 1 },
  "is_target_success",
  { data_type => "boolean", is_nullable => 1 },
  "is_final",
  { data_type => "boolean", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:K0WEd4EZMZ9YpSfYXJlqKw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
