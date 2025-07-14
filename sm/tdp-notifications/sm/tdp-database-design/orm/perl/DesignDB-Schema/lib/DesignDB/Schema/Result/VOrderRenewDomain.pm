use utf8;
package DesignDB::Schema::Result::VOrderRenewDomain;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VOrderRenewDomain

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

=head1 TABLE: C<v_order_renew_domain>

=cut 

__PACKAGE__->table("v_order_renew_domain");
__PACKAGE__->result_source_instance->view_definition(" SELECT rd.id AS order_item_id,\n    rd.order_id,\n    rd.accreditation_tld_id,\n    o.tenant_customer_id,\n    o.type_id,\n    o.customer_user_id,\n    o.status_id,\n    s.name AS status_name,\n    s.descr AS status_descr,\n    tc.tenant_id,\n    tc.customer_id,\n    tc.tenant_name,\n    tc.name,\n    at.provider_name,\n    at.provider_instance_id,\n    at.provider_instance_name,\n    at.tld_id,\n    at.tld_name,\n    at.accreditation_id,\n    d.name AS domain_name,\n    d.id AS domain_id,\n    rd.period,\n    rd.current_expiry_date\n   FROM ((((((order_item_renew_domain rd\n     JOIN \"order\" o ON ((o.id = rd.order_id)))\n     JOIN v_order_type ot ON ((ot.id = o.type_id)))\n     JOIN v_tenant_customer tc ON ((tc.id = o.tenant_customer_id)))\n     JOIN order_status s ON ((s.id = o.status_id)))\n     JOIN v_accreditation_tld at ON ((at.accreditation_tld_id = rd.accreditation_tld_id)))\n     JOIN domain d ON (((d.tenant_customer_id = o.tenant_customer_id) AND (d.name = (rd.name)::text))))");

=head1 ACCESSORS

=head2 order_item_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 order_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 accreditation_tld_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tenant_customer_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 type_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 customer_user_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 status_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 status_name

  data_type: 'text'
  is_nullable: 1

=head2 status_descr

  data_type: 'text'
  is_nullable: 1

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

=head2 name

  data_type: 'text'
  is_nullable: 1

=head2 provider_name

  data_type: 'text'
  is_nullable: 1

=head2 provider_instance_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_instance_name

  data_type: 'text'
  is_nullable: 1

=head2 tld_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tld_name

  data_type: 'text'
  is_nullable: 1

=head2 accreditation_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 domain_name

  data_type: 'text'
  is_nullable: 1

=head2 domain_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 period

  data_type: 'integer'
  is_nullable: 1

=head2 current_expiry_date

  data_type: 'timestamp with time zone'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "order_item_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "order_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "accreditation_tld_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_customer_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "type_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "customer_user_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "status_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "status_name",
  { data_type => "text", is_nullable => 1 },
  "status_descr",
  { data_type => "text", is_nullable => 1 },
  "tenant_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "customer_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_name",
  { data_type => "text", is_nullable => 1 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "provider_name",
  { data_type => "text", is_nullable => 1 },
  "provider_instance_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_instance_name",
  { data_type => "text", is_nullable => 1 },
  "tld_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tld_name",
  { data_type => "text", is_nullable => 1 },
  "accreditation_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "domain_name",
  { data_type => "text", is_nullable => 1 },
  "domain_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "period",
  { data_type => "integer", is_nullable => 1 },
  "current_expiry_date",
  { data_type => "timestamp with time zone", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:6/2rcS8XvHcA47Hk50mH4Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
