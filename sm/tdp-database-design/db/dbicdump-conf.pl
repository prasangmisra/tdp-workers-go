#! /usr/bin/perl

# This configuration file contains the settings required for
# generating the DBIx::Class result modules from the currently
# deployed schema.

use common::sense;
use Pod::Abstract;
use File::Path qw(make_path);

BEGIN {
  use lib '../DesignDB-Schema/lib';
}

# We need to do this to insure that POD directives are in the
# canonical format that Pod::Abstract produces.

sub normalize_pod {
  my ( $type, $class, $text ) = @_;
  my $pa = Pod::Abstract->load_string( $text );

  my $result = $pa->pod;
  $result =~ s{^=cut(?! )}{=cut }gms;

  return $result;
}

# The returned config itself.

my $config = {

  schema_class => 'DesignDB::Schema',

  connect_info => {
    dsn => $ENV{DBI_DSN} // sprintf(
      'dbi:Pg:database=%s;host=%s;port=%d',
      $ENV{DBNAME}, $ENV{DBHOST}, $ENV{DBPORT}
    ),
    user => $ENV{DBUSER} // $ENV{DBI_USER},
    pass => $ENV{DBPASS} // $ENV{DBI_PASS},
  },

  loader_options => {
    components              => [qw{ InflateColumn::DateTime }],
    use_moose               => 1,
    dump_directory          => '../orm/perl/DesignDB-Schema/lib',
    # result_roles            => [qw(DesignDB::Schema::Role::Hash)],
    skip_load_external      => 1,
    filter_generated_code   => \&normalize_pod,
    exclude                 => qr/^_/,
    moniker_map             => {},
    col_accessor_map        => {},
    overwrite_modifications => 1,
    omit_timestamp          => 1,
  },

};

my $err;
my @created =
  make_path( $config->{loader_options}->{dump_directory}, { error => \$err } );

if ( scalar @{$err} > 0 ) {
  use Data::Dumper;
  die( q{cannot create dump directory: } . Dumper( $err ) );
}

return $config;
