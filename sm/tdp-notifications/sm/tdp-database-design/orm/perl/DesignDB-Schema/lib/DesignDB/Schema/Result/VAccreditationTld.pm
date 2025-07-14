use utf8;
package DesignDB::Schema::Result::VAccreditationTld;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::VAccreditationTld

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

=head1 TABLE: C<v_accreditation_tld>

=cut 

__PACKAGE__->table("v_accreditation_tld");
__PACKAGE__->result_source_instance->view_definition(" SELECT a.tenant_id,\n    a.id AS accreditation_id,\n    a.name AS accreditation_name,\n    at.id AS accreditation_tld_id,\n    tnc.id AS tenant_customer_id,\n    tnc.customer_number AS tenant_customer_number,\n    c.id AS customer_id,\n    c.name AS customer_name,\n    t.id AS tld_id,\n    t.name AS tld_name,\n    p.name AS provider_name,\n    p.id AS provider_id,\n    pi.id AS provider_instance_id,\n    pi.name AS provider_instance_name,\n    pi.is_proxy,\n    at.is_default\n   FROM ((((((((accreditation a\n     JOIN tenant tn ON ((tn.id = a.tenant_id)))\n     JOIN tenant_customer tnc ON ((tnc.tenant_id = tn.id)))\n     JOIN customer c ON ((c.id = tnc.customer_id)))\n     JOIN accreditation_tld at ON ((at.accreditation_id = a.id)))\n     JOIN provider_instance_tld pit ON (((pit.id = at.provider_instance_tld_id) AND (pit.service_range \@> now()))))\n     JOIN provider_instance pi ON (((pi.id = pit.provider_instance_id) AND (a.provider_instance_id = pi.id))))\n     JOIN provider p ON ((p.id = pi.provider_id)))\n     JOIN tld t ON ((t.id = pit.tld_id)))");

=head1 ACCESSORS

=head2 tenant_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 accreditation_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 accreditation_name

  data_type: 'text'
  is_nullable: 1

=head2 accreditation_tld_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tenant_customer_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tenant_customer_number

  data_type: 'text'
  is_nullable: 1

=head2 customer_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 customer_name

  data_type: 'text'
  is_nullable: 1

=head2 tld_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 tld_name

  data_type: 'text'
  is_nullable: 1

=head2 provider_name

  data_type: 'text'
  is_nullable: 1

=head2 provider_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_instance_id

  data_type: 'uuid'
  is_nullable: 1
  size: 16

=head2 provider_instance_name

  data_type: 'text'
  is_nullable: 1

=head2 is_proxy

  data_type: 'boolean'
  is_nullable: 1

=head2 is_default

  data_type: 'boolean'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "tenant_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "accreditation_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "accreditation_name",
  { data_type => "text", is_nullable => 1 },
  "accreditation_tld_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_customer_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tenant_customer_number",
  { data_type => "text", is_nullable => 1 },
  "customer_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "customer_name",
  { data_type => "text", is_nullable => 1 },
  "tld_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "tld_name",
  { data_type => "text", is_nullable => 1 },
  "provider_name",
  { data_type => "text", is_nullable => 1 },
  "provider_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_instance_id",
  { data_type => "uuid", is_nullable => 1, size => 16 },
  "provider_instance_name",
  { data_type => "text", is_nullable => 1 },
  "is_proxy",
  { data_type => "boolean", is_nullable => 1 },
  "is_default",
  { data_type => "boolean", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eZQ3XQIXcXePK4FvanoIrA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
