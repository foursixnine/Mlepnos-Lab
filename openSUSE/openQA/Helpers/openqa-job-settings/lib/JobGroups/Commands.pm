# Minimal Mojolicious::Commands container for JobGroups CLI
package JobGroups::Commands;
use Mojo::Base 'Mojolicious::Commands', -signatures;

# subcommand classes live under JobGroups::Command::
has namespaces => sub { ['JobGroups::Command'] };

has message => 'JobGroups CLI - commands for working with openQA products';

$SIG{__DIE__} = \&Carp::confess;

1;
