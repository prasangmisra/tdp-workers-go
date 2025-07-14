use utf8;
package DesignDB::Schema::Result::OrderStatusPath;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::OrderStatusPath

=head1 DESCRIPTION

Names the valid "paths" that an order can take, this allows for flexibility on the possibility
of using multiple payment methods that may or may not offer auth/capture.

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

=head1 TABLE: C<order_status_path>

=cut 

__PACKAGE__->table("order_status_path");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 descr

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
  "name",
  { data_type => "text", is_nullable => 0 },
  "descr",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<order_status_path_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("order_status_path_name_key", ["name"]);

=head1 RELATIONS

=head2 order_status_transitions

Type: has_many

Related object: L<DesignDB::Schema::Result::OrderStatusTransition>

=cut 

__PACKAGE__->has_many(
  "order_status_transitions",
  "DesignDB::Schema::Result::OrderStatusTransition",
  { "foreign.path_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 orders

Type: has_many

Related object: L<DesignDB::Schema::Result::Order>

=cut 

__PACKAGE__->has_many(
  "orders",
  "DesignDB::Schema::Result::Order",
  { "foreign.path_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:OGsVh8C3Ez3KaB/Zx2Uojw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
