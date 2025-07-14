use utf8;
package DesignDB::Schema::Result::VOrderItemPlanObject;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VOrderItemPlanObject

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

=head1 TABLE: C<v_order_item_plan_object>

=cut 

__PACKAGE__->table("v_order_item_plan_object");
__PACKAGE__->result_source_instance->view_definition(" SELECT d.id AS order_item_id,\n    p.name AS product_name,\n    ot.name AS order_type_name,\n    obj.name AS object_name,\n    obj.id AS object_id,\n    distinct_order_contact.id\n   FROM (((((order_item_create_domain d\n     JOIN \"order\" o ON ((o.id = d.order_id)))\n     JOIN order_type ot ON ((ot.id = o.type_id)))\n     JOIN product p ON ((p.id = ot.product_id)))\n     JOIN order_item_object obj ON ((obj.name = 'contact'::text)))\n     JOIN LATERAL ( SELECT DISTINCT create_domain_contact.order_contact_id AS id\n           FROM create_domain_contact\n          WHERE (create_domain_contact.create_domain_id = d.id)) distinct_order_contact ON (true))\nUNION\n SELECT d.id AS order_item_id,\n    p.name AS product_name,\n    ot.name AS order_type_name,\n    obj.name AS object_name,\n    obj.id AS object_id,\n    distinct_order_host.id\n   FROM (((((order_item_create_domain d\n     JOIN \"order\" o ON ((o.id = d.order_id)))\n     JOIN order_type ot ON ((ot.id = o.type_id)))\n     JOIN product p ON ((p.id = ot.product_id)))\n     JOIN order_item_object obj ON ((obj.name = 'host'::text)))\n     JOIN LATERAL ( SELECT DISTINCT create_domain_nameserver.id\n           FROM create_domain_nameserver\n          WHERE (create_domain_nameserver.create_domain_id = d.id)) distinct_order_host ON (true))\nUNION\n SELECT d.id AS order_item_id,\n    p.name AS product_name,\n    ot.name AS order_type_name,\n    obj.name AS object_name,\n    obj.id AS object_id,\n    d.id\n   FROM ((((order_item_create_domain d\n     JOIN \"order\" o ON ((o.id = d.order_id)))\n     JOIN order_type ot ON ((ot.id = o.type_id)))\n     JOIN product p ON ((p.id = ot.product_id)))\n     JOIN order_item_object obj ON ((obj.name = 'domain'::text)))\nUNION\n SELECT d.id AS order_item_id,\n    p.name AS product_name,\n    ot.name AS order_type_name,\n    obj.name AS object_name,\n    obj.id AS object_id,\n    d.id\n   FROM ((((order_item_renew_domain d\n     JOIN \"order\" o ON ((o.id = d.order_id)))\n     JOIN order_type ot ON ((ot.id = o.type_id)))\n     JOIN product p ON ((p.id = ot.product_id)))\n     JOIN order_item_object obj ON ((obj.name = 'domain'::text)))");

=head1 ACCESSORS

=head2 order_item_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 product_name

  data_type: 'text'
  is_nullable: 1

=head2 order_type_name

  data_type: 'text'
  is_nullable: 1

=head2 object_name

  data_type: 'text'
  is_nullable: 1

=head2 object_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=cut 

__PACKAGE__->add_columns(
  "order_item_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "product_name",
  { data_type => "text", is_nullable => 1 },
  "order_type_name",
  { data_type => "text", is_nullable => 1 },
  "object_name",
  { data_type => "text", is_nullable => 1 },
  "object_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:v6UoePYeKtpq4QBIJchZlA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
