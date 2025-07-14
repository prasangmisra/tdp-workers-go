use utf8;
package DesignDB::Schema::Result::AccreditationTld;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::AccreditationTld - tlds covered by an accreditation

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

=head1 TABLE: C<accreditation_tld>

=cut 

__PACKAGE__->table("accreditation_tld");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  default_value: gen_random_uuid()
  is_nullable: 0
  size: 16

=head2 accreditation_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 provider_instance_tld_id

  data_type: 'uuid'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 is_default

  data_type: 'boolean'
  default_value: true
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
  "accreditation_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "provider_instance_tld_id",
  { data_type => "uuid", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "is_default",
  { data_type => "boolean", default_value => \"true", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut 

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<accreditation_tld_accreditation_id_provider_instance_tld_id_key>

=over 4

=item * L</accreditation_id>

=item * L</provider_instance_tld_id>

=back

=cut 

__PACKAGE__->add_unique_constraint(
  "accreditation_tld_accreditation_id_provider_instance_tld_id_key",
  ["accreditation_id", "provider_instance_tld_id"],
);

=head1 RELATIONS

=head2 accreditation

Type: belongs_to

Related object: L<DesignDB::Schema::Result::Accreditation>

=cut 

__PACKAGE__->belongs_to(
  "accreditation",
  "DesignDB::Schema::Result::Accreditation",
  { id => "accreditation_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 domains

Type: has_many

Related object: L<DesignDB::Schema::Result::Domain>

=cut 

__PACKAGE__->has_many(
  "domains",
  "DesignDB::Schema::Result::Domain",
  { "foreign.accreditation_tld_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 order_item_create_domains

Type: has_many

Related object: L<DesignDB::Schema::Result::OrderItemCreateDomain>

=cut 

__PACKAGE__->has_many(
  "order_item_create_domains",
  "DesignDB::Schema::Result::OrderItemCreateDomain",
  { "foreign.accreditation_tld_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 order_item_renew_domains

Type: has_many

Related object: L<DesignDB::Schema::Result::OrderItemRenewDomain>

=cut 

__PACKAGE__->has_many(
  "order_item_renew_domains",
  "DesignDB::Schema::Result::OrderItemRenewDomain",
  { "foreign.accreditation_tld_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 provider_instance_tld

Type: belongs_to

Related object: L<DesignDB::Schema::Result::ProviderInstanceTld>

=cut 

__PACKAGE__->belongs_to(
  "provider_instance_tld",
  "DesignDB::Schema::Result::ProviderInstanceTld",
  { id => "provider_instance_tld_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 provision_domains

Type: has_many

Related object: L<DesignDB::Schema::Result::ProvisionDomain>

=cut 

__PACKAGE__->has_many(
  "provision_domains",
  "DesignDB::Schema::Result::ProvisionDomain",
  { "foreign.accreditation_tld_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:YqDkAGbLZp3q9RA8aNzK6g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
