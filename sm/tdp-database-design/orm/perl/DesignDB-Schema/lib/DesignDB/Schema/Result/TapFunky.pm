use utf8;
package DesignDB::Schema::Result::TapFunky;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::TapFunky

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

=head1 TABLE: C<tap_funky>

=cut 

__PACKAGE__->table("tap_funky");
__PACKAGE__->result_source_instance->view_definition(" SELECT p.oid,\n    n.nspname AS schema,\n    p.proname AS name,\n    pg_get_userbyid(p.proowner) AS owner,\n    array_to_string((p.proargtypes)::regtype[], ','::text) AS args,\n    (\n        CASE p.proretset\n            WHEN true THEN 'setof '::text\n            ELSE ''::text\n        END || (p.prorettype)::regtype) AS returns,\n    p.prolang AS langoid,\n    p.proisstrict AS is_strict,\n    _prokind(p.oid) AS kind,\n    p.prosecdef AS is_definer,\n    p.proretset AS returns_set,\n    (p.provolatile)::character(1) AS volatility,\n    pg_function_is_visible(p.oid) AS is_visible\n   FROM (pg_proc p\n     JOIN pg_namespace n ON ((p.pronamespace = n.oid)))");

=head1 ACCESSORS

=head2 oid

  data_type: 'oid'
  is_nullable: 1
  size: 4

=head2 schema

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 name

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 owner

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 args

  data_type: 'text'
  is_nullable: 1

=head2 returns

  data_type: 'text'
  is_nullable: 1

=head2 langoid

  data_type: 'oid'
  is_nullable: 1
  size: 4

=head2 is_strict

  data_type: 'boolean'
  is_nullable: 1

=head2 kind

  data_type: '"char"'
  is_nullable: 1
  size: 1

=head2 is_definer

  data_type: 'boolean'
  is_nullable: 1

=head2 returns_set

  data_type: 'boolean'
  is_nullable: 1

=head2 volatility

  data_type: 'char'
  is_nullable: 1
  size: 1

=head2 is_visible

  data_type: 'boolean'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "oid",
  { data_type => "oid", is_nullable => 1, size => 4 },
  "schema",
  { data_type => "name", is_nullable => 1, size => 64 },
  "name",
  { data_type => "name", is_nullable => 1, size => 64 },
  "owner",
  { data_type => "name", is_nullable => 1, size => 64 },
  "args",
  { data_type => "text", is_nullable => 1 },
  "returns",
  { data_type => "text", is_nullable => 1 },
  "langoid",
  { data_type => "oid", is_nullable => 1, size => 4 },
  "is_strict",
  { data_type => "boolean", is_nullable => 1 },
  "kind",
  { data_type => "\"char\"", is_nullable => 1, size => 1 },
  "is_definer",
  { data_type => "boolean", is_nullable => 1 },
  "returns_set",
  { data_type => "boolean", is_nullable => 1 },
  "volatility",
  { data_type => "char", is_nullable => 1, size => 1 },
  "is_visible",
  { data_type => "boolean", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:dXqfqZxYA2PHjLwVdyUZuQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
