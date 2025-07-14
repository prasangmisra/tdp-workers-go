use utf8;
package DesignDB::Schema::Result::OrderItemStrategy;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::OrderItemStrategy

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

=head1 TABLE: C<order_item_strategy>

=cut 

__PACKAGE__->table("order_item_strategy");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 order_type_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 provider_instance_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 1
  size: 16

=head2 object_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 provision_order

  data_type: 'integer'
  default_value: 1
  is_nullable: 0

=cut 

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "uuid",
    default_value => \"gen_random_uuid()",
    is_nullable => 0,
    size => 16,
  },
  "order_type_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "provider_instance_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 1, size => 16 },
  "object_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "provision_order",
  { data_type => "integer", default_value => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 object

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderItemObject>

=cut 

__PACKAGE__->belongs_to(
  "object",
  "DesignDB::Schema::Result::OrderItemObject",
  { id => "object_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 order_type

Type: belongs_to

Related object: L<DesignDB::Schema::Result::OrderType>

=cut 

__PACKAGE__->belongs_to(
  "order_type",
  "DesignDB::Schema::Result::OrderType",
  { id => "order_type_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 provider_instance

Type: belongs_to

Related object: L<DesignDB::Schema::Result::ProviderInstance>

=cut 

__PACKAGE__->belongs_to(
  "provider_instance",
  "DesignDB::Schema::Result::ProviderInstance",
  { id => "provider_instance_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:vc9XeqYt3OnsLhZEvMWs8Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
