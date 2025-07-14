use utf8;
package DesignDB::Schema::Result::OrderItemStatus;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::OrderItemStatus

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

=head1 TABLE: C<order_item_status>

=cut 

__PACKAGE__->table("order_item_status");

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
  is_nullable: 0

=head2 is_final

  data_type: 'boolean'
  is_nullable: 0

=head2 is_success

  data_type: 'boolean'
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
  "name",
  { data_type => "text", is_nullable => 0 },
  "descr",
  { data_type => "text", is_nullable => 0 },
  "is_final",
  { data_type => "boolean", is_nullable => 0 },
  "is_success",
  { data_type => "boolean", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<order_item_status_name_key>

=over 4

=item * L</name>

=back

=cut 

__PACKAGE__->add_unique_constraint("order_item_status_name_key", ["name"]);

=head1 RELATIONS

=head2 order_item_create_domains

Type: has_many

Related object: L<DesignDB::Schema::Result::OrderItemCreateDomain>

=cut 

__PACKAGE__->has_many(
  "order_item_create_domains",
  "DesignDB::Schema::Result::OrderItemCreateDomain",
  { "foreign.status_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 order_item_renew_domains

Type: has_many

Related object: L<DesignDB::Schema::Result::OrderItemRenewDomain>

=cut 

__PACKAGE__->has_many(
  "order_item_renew_domains",
  "DesignDB::Schema::Result::OrderItemRenewDomain",
  { "foreign.status_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 order_items

Type: has_many

Related object: L<DesignDB::Schema::Result::OrderItem>

=cut 

__PACKAGE__->has_many(
  "order_items",
  "DesignDB::Schema::Result::OrderItem",
  { "foreign.status_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Vf+0ZXIjUSymcjFagaT+OQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
