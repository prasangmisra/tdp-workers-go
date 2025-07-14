use utf8;
package DesignDB::Schema::Result::VOrder;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VOrder

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

=head1 TABLE: C<v_order>

=cut 

__PACKAGE__->table("v_order");
__PACKAGE__->result_source_instance->view_definition(" SELECT o.id AS order_id,\n    p.id AS product_id,\n    ot.id AS order_type_id,\n    osp.id AS order_path_id,\n    os.id AS order_status_id,\n    tc.id AS tenant_customer_id,\n    t.id AS tenant_id,\n    c.id AS customer_id,\n    p.name AS product_name,\n    ot.name AS order_type_name,\n    osp.name AS order_path_name,\n    os.name AS order_status_name,\n    t.name AS tenant_name,\n    c.name AS customer_name,\n    os.is_final AS order_status_is_final,\n    os.is_success AS order_status_is_success,\n    o.created_date,\n    o.updated_date,\n    (o.updated_date - o.created_date) AS elapsed\n   FROM (((((((\"order\" o\n     JOIN order_status os ON ((os.id = o.status_id)))\n     JOIN order_status_path osp ON ((osp.id = o.path_id)))\n     JOIN order_type ot ON ((ot.id = o.type_id)))\n     JOIN product p ON ((p.id = ot.product_id)))\n     JOIN tenant_customer tc ON ((tc.id = o.tenant_customer_id)))\n     JOIN tenant t ON ((t.id = tc.tenant_id)))\n     JOIN customer c ON ((c.id = tc.customer_id)))");

=head1 ACCESSORS

=head2 order_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 product_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_type_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_path_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_status_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tenant_customer_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tenant_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 customer_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 product_name

  data_type: 'text'
  is_nullable: 1

=head2 order_type_name

  data_type: 'text'
  is_nullable: 1

=head2 order_path_name

  data_type: 'text'
  is_nullable: 1

=head2 order_status_name

  data_type: 'text'
  is_nullable: 1

=head2 tenant_name

  data_type: 'text'
  is_nullable: 1

=head2 customer_name

  data_type: 'text'
  is_nullable: 1

=head2 order_status_is_final

  data_type: 'boolean'
  is_nullable: 1

=head2 order_status_is_success

  data_type: 'boolean'
  is_nullable: 1

=head2 created_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 updated_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 elapsed

  data_type: 'interval'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "order_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "product_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_type_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_path_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_status_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_customer_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "customer_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "product_name",
  { data_type => "text", is_nullable => 1 },
  "order_type_name",
  { data_type => "text", is_nullable => 1 },
  "order_path_name",
  { data_type => "text", is_nullable => 1 },
  "order_status_name",
  { data_type => "text", is_nullable => 1 },
  "tenant_name",
  { data_type => "text", is_nullable => 1 },
  "customer_name",
  { data_type => "text", is_nullable => 1 },
  "order_status_is_final",
  { data_type => "boolean", is_nullable => 1 },
  "order_status_is_success",
  { data_type => "boolean", is_nullable => 1 },
  "created_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "updated_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "elapsed",
  { data_type => "interval", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:LbBEz4VzYlFVjSSgEJOSgA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
