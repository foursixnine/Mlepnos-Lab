# Fake OpenQA::Client for unit tests
package OpenQA::Client;
use strict;
use warnings;
use Mojo::URL;

our $LAST_CLIENT;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        apikey => $args{apikey},
        apisecret => $args{apisecret},
        base_url => Mojo::URL->new('http://localhost'),
        calls => [],
    }, $class;
    $LAST_CLIENT = $self;
    return $self;
}

sub base_url { my ($self, $u) = @_; $self->{base_url} = $u if $u; return $self->{base_url} }
sub ioloop {};
sub transactor { bless {}, 'Transactor' }

sub build_tx { my ($self, $method, $url, @rest) = @_; return { method => $method, url => $url, args => {@rest} } }
sub start { my ($self, $tx, $cb) = @_; push @{$self->{calls}}, $tx; if ($cb) { $cb->($self, { res => FakeRes->new({ is_success => 1, json => { products => [ { id => 1, name => 'prod', VERSION => '16.0' } ] } }) }) } return FakeTx->new({ res => FakeRes->new({ is_success => 1, json => { products => [ { id => 1, name => 'prod', VERSION => '16.0' } ] } }) }) }

package FakeTx;
sub new { bless $_[1], __PACKAGE__ }
sub res { return $_[0]{res} }

package FakeRes;
sub new { bless $_[1], __PACKAGE__ }
sub is_success { return $_[0]{is_success} }
sub json { return $_[0]{json} }
sub code { return $_[0]{code} }
sub message { return $_[0]{message} }

1;
