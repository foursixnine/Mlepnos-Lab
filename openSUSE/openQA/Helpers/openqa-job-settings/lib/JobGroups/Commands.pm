# Minimal Mojolicious::Commands container for JobGroups CLI
package JobGroups::Commands;
use Mojo::Base 'Mojolicious::Commands', -signatures;

has namespaces => sub { ['JobGroups::Command'] };
has message => 'JobGroups CLI - commands for working with openQA products';

1;
