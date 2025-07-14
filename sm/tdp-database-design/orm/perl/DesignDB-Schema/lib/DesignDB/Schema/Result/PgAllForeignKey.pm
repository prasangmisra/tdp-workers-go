use utf8;
package DesignDB::Schema::Result::PgAllForeignKey;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DesignDB::Schema::Result::PgAllForeignKey

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

=head1 TABLE: C<pg_all_foreign_keys>

=cut 

__PACKAGE__->table("pg_all_foreign_keys");
__PACKAGE__->result_source_instance->view_definition(" SELECT n1.nspname AS fk_schema_name,\n    c1.relname AS fk_table_name,\n    k1.conname AS fk_constraint_name,\n    c1.oid AS fk_table_oid,\n    _pg_sv_column_array(k1.conrelid, k1.conkey) AS fk_columns,\n    n2.nspname AS pk_schema_name,\n    c2.relname AS pk_table_name,\n    k2.conname AS pk_constraint_name,\n    c2.oid AS pk_table_oid,\n    ci.relname AS pk_index_name,\n    _pg_sv_column_array(k1.confrelid, k1.confkey) AS pk_columns,\n        CASE k1.confmatchtype\n            WHEN 'f'::\"char\" THEN 'FULL'::text\n            WHEN 'p'::\"char\" THEN 'PARTIAL'::text\n            WHEN 'u'::\"char\" THEN 'NONE'::text\n            ELSE NULL::text\n        END AS match_type,\n        CASE k1.confdeltype\n            WHEN 'a'::\"char\" THEN 'NO ACTION'::text\n            WHEN 'c'::\"char\" THEN 'CASCADE'::text\n            WHEN 'd'::\"char\" THEN 'SET DEFAULT'::text\n            WHEN 'n'::\"char\" THEN 'SET NULL'::text\n            WHEN 'r'::\"char\" THEN 'RESTRICT'::text\n            ELSE NULL::text\n        END AS on_delete,\n        CASE k1.confupdtype\n            WHEN 'a'::\"char\" THEN 'NO ACTION'::text\n            WHEN 'c'::\"char\" THEN 'CASCADE'::text\n            WHEN 'd'::\"char\" THEN 'SET DEFAULT'::text\n            WHEN 'n'::\"char\" THEN 'SET NULL'::text\n            WHEN 'r'::\"char\" THEN 'RESTRICT'::text\n            ELSE NULL::text\n        END AS on_update,\n    k1.condeferrable AS is_deferrable,\n    k1.condeferred AS is_deferred\n   FROM ((((((((pg_constraint k1\n     JOIN pg_namespace n1 ON ((n1.oid = k1.connamespace)))\n     JOIN pg_class c1 ON ((c1.oid = k1.conrelid)))\n     JOIN pg_class c2 ON ((c2.oid = k1.confrelid)))\n     JOIN pg_namespace n2 ON ((n2.oid = c2.relnamespace)))\n     JOIN pg_depend d ON (((d.classid = ('pg_constraint'::regclass)::oid) AND (d.objid = k1.oid) AND (d.objsubid = 0) AND (d.deptype = 'n'::\"char\") AND (d.refclassid = ('pg_class'::regclass)::oid) AND (d.refobjsubid = 0))))\n     JOIN pg_class ci ON (((ci.oid = d.refobjid) AND (ci.relkind = 'i'::\"char\"))))\n     LEFT JOIN pg_depend d2 ON (((d2.classid = ('pg_class'::regclass)::oid) AND (d2.objid = ci.oid) AND (d2.objsubid = 0) AND (d2.deptype = 'i'::\"char\") AND (d2.refclassid = ('pg_constraint'::regclass)::oid) AND (d2.refobjsubid = 0))))\n     LEFT JOIN pg_constraint k2 ON (((k2.oid = d2.refobjid) AND (k2.contype = ANY (ARRAY['p'::\"char\", 'u'::\"char\"])))))\n  WHERE ((k1.conrelid <> (0)::oid) AND (k1.confrelid <> (0)::oid) AND (k1.contype = 'f'::\"char\") AND _pg_sv_table_accessible(n1.oid, c1.oid))");

=head1 ACCESSORS

=head2 fk_schema_name

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 fk_table_name

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 fk_constraint_name

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 fk_table_oid

  data_type: 'oid'
  is_nullable: 1
  size: 4

=head2 fk_columns

  data_type: 'name[]'
  is_nullable: 1

=head2 pk_schema_name

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 pk_table_name

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 pk_constraint_name

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 pk_table_oid

  data_type: 'oid'
  is_nullable: 1
  size: 4

=head2 pk_index_name

  data_type: 'name'
  is_nullable: 1
  size: 64

=head2 pk_columns

  data_type: 'name[]'
  is_nullable: 1

=head2 match_type

  data_type: 'text'
  is_nullable: 1

=head2 on_delete

  data_type: 'text'
  is_nullable: 1

=head2 on_update

  data_type: 'text'
  is_nullable: 1

=head2 is_deferrable

  data_type: 'boolean'
  is_nullable: 1

=head2 is_deferred

  data_type: 'boolean'
  is_nullable: 1

=cut 

__PACKAGE__->add_columns(
  "fk_schema_name",
  { data_type => "name", is_nullable => 1, size => 64 },
  "fk_table_name",
  { data_type => "name", is_nullable => 1, size => 64 },
  "fk_constraint_name",
  { data_type => "name", is_nullable => 1, size => 64 },
  "fk_table_oid",
  { data_type => "oid", is_nullable => 1, size => 4 },
  "fk_columns",
  { data_type => "name[]", is_nullable => 1 },
  "pk_schema_name",
  { data_type => "name", is_nullable => 1, size => 64 },
  "pk_table_name",
  { data_type => "name", is_nullable => 1, size => 64 },
  "pk_constraint_name",
  { data_type => "name", is_nullable => 1, size => 64 },
  "pk_table_oid",
  { data_type => "oid", is_nullable => 1, size => 4 },
  "pk_index_name",
  { data_type => "name", is_nullable => 1, size => 64 },
  "pk_columns",
  { data_type => "name[]", is_nullable => 1 },
  "match_type",
  { data_type => "text", is_nullable => 1 },
  "on_delete",
  { data_type => "text", is_nullable => 1 },
  "on_update",
  { data_type => "text", is_nullable => 1 },
  "is_deferrable",
  { data_type => "boolean", is_nullable => 1 },
  "is_deferred",
  { data_type => "boolean", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07049
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:t9lhkxfCODlbTskIcLpOQg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
