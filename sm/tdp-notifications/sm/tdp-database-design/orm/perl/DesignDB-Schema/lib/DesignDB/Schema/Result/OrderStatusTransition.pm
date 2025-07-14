use utf8;
package DesignDB::Schema::Result::OrderStatusTransition;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::OrderStatusTransition

=head1 DESCRIPTION

tuples in this table become valid status transitions for orders

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

=head1 TABLE: C<order_status_transition>

=cut 

__PACKAGE__->table("order_status_transition");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 path_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 from_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 to_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=cut 

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "path_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "from_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "to_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<order_status_transition_path_id_from_id_to_id_key>

=over 4

=item * L</path_id>

=item * L</from_id>

=item * L</to_id>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "order_status_transition_path_id_from_id_to_id_key",
  ["path_id", "from_id", "to_id"],
);

=head1 RELATIONS

=head2 from

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderStatus>

=cut 

__PACKAGE__->belongs_to(
  "from",
  "DesignDB::Schema::Result::OrderStatus",
  { id => "from_id" },
  { is_deferrable => 0, on_delete => "CASCADE", on_update => "NO ACTION" },
);

=head2 path

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderStatusPath>

=cut 

__PACKAGE__->belongs_to(
  "path",
  "DesignDB::Schema::Result::OrderStatusPath",
  { id => "path_id" },
  { is_deferrable => 0, on_delete => "CASCADE", on_update => "NO ACTION" },
);

=head2 to

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderStatus>

=cut 

__PACKAGE__->belongs_to(
  "to",
  "DesignDB::Schema::Result::OrderStatus",
  { id => "to_id" },
  { is_deferrable => 0, on_delete => "CASCADE", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:9Ll/FGIYzk6WHEmIV9uoqw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
