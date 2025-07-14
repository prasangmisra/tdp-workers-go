use utf8;
package DesignDB::Schema::Result::VTenantCustomer;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VTenantCustomer

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

=head1 TABLE: C<v_tenant_customer>

=cut 

__PACKAGE__->table("v_tenant_customer");
__PACKAGE__->result_source_instance->view_definition(" SELECT tc.tenant_id,\n    tc.customer_id,\n    t.name AS tenant_name,\n    t.descr AS tenant_descr,\n    tc.customer_number,\n    tc.id,\n    c.name,\n    c.descr,\n    c.created_date AS customer_created_date,\n    c.updated_date AS customer_updated_date,\n    tc.created_date AS tenant_customer_created_date,\n    tc.updated_date AS tenant_customer_updated_date\n   FROM ((tenant_customer tc\n     JOIN tenant t ON ((t.id = tc.tenant_id)))\n     JOIN customer c ON ((c.id = tc.customer_id)))");

=head1 ACCESSORS

=head2 tenant_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 customer_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tenant_name

  data_type: 'text'
  is_nullable: 1

=head2 tenant_descr

  data_type: 'text'
  is_nullable: 1

=head2 customer_number

  data_type: 'text'
  is_nullable: 1

=head2 id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 name

  data_type: 'text'
  is_nullable: 1

=head2 descr

  data_type: 'text'
  is_nullable: 1

=head2 customer_created_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 customer_updated_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 tenant_customer_created_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=head2 tenant_customer_updated_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "tenant_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "customer_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_name",
  { data_type => "text", is_nullable => 1 },
  "tenant_descr",
  { data_type => "text", is_nullable => 1 },
  "customer_number",
  { data_type => "text", is_nullable => 1 },
  "id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "descr",
  { data_type => "text", is_nullable => 1 },
  "customer_created_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "customer_updated_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "tenant_customer_created_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
  "tenant_customer_updated_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:oYiJk9C6QhTsb/AlTVeD1A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
