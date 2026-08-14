use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::RealBin/../lib";

use IO::Socket::INET;
use Mojo::JSON qw(decode_json);
use Mojo::Server::Daemon;
use Mojolicious::Lite;
use Test::Mojo;

my %products = (
    201 => {
        id          => 201,
        distri      => 'mockdistri',
        version     => '16.0',
        arch        => 'x86_64',
        flavor      => 'default',
        description => 'mock',
        settings    => [ { key => 'VERSION', value => '16.0' } ],
    },
);
my $next_product_id = 202;
my $requests = [];

my $app = app;

$app->routes->get('/api/v1/products' => sub {
    my $c = shift;
    push @$requests, { method => 'GET', path => '/api/v1/products' };
    my @list = map { $products{$_} } sort { $a <=> $b } keys %products;
    $c->render(json => { Products => \@list });
});

$app->routes->get('/api/v1/products/:id' => sub {
    my $c = shift;
    my $id = $c->param('id');
    push @$requests, { method => 'GET', path => "/api/v1/products/$id" };
    if ($products{$id}) {
        $c->render(json => { product => $products{$id} });
    }
    else {
        $c->render(json => { error => 'Not found' }, status => 404);
    }
});

$app->routes->post('/api/v1/products' => sub {
    my $c = shift;
    my $data = eval { decode_json($c->req->body || '{}') } || {};
    push @$requests, { method => 'POST', path => '/api/v1/products', body => $c->req->body };
    my $id = $next_product_id++;
    $data->{id} = $id;
    $data->{settings} ||= [];
    $products{$id} = $data;
    $c->render(json => { id => $id });
});

$app->routes->put('/api/v1/products/:id' => sub {
    my $c = shift;
    my $id = $c->param('id');
    my $data = eval { decode_json($c->req->body || '{}') } || {};
    push @$requests, { method => 'PUT', path => "/api/v1/products/$id", body => $c->req->body };
    if ($products{$id}) {
        for my $k (keys %$data) {
            $products{$id}{$k} = $data->{$k};
        }
        if (ref $data->{settings} eq 'HASH') {
            my @settings = map { { key => $_, value => $data->{settings}{$_} } } keys %{ $data->{settings} };
            $products{$id}{settings} = \@settings;
        }
        $c->render(json => { result => 1 });
    }
    else {
        $c->render(json => { error => 'Not found' }, status => 404);
    }
});

$app->routes->delete('/api/v1/products/:id' => sub {
    my $c = shift;
    my $id = $c->param('id');
    push @$requests, { method => 'DELETE', path => "/api/v1/products/$id" };
    delete $products{$id};
    $c->render(json => { result => 1 });
});

$app->routes->get('/__requests' => sub {
    my $c = shift;
    $c->render(json => $requests);
});

my $sock = IO::Socket::INET->new(
    Listen    => 1,
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Proto     => 'tcp',
) or die "cannot get free port: $!";
my $port = $sock->sockport;
close $sock;

my $daemon = Mojo::Server::Daemon->new(app => $app, listen => ["http://127.0.0.1:$port"]);
$daemon->start;

my $host = "127.0.0.1:$port";
my $t = Test::Mojo->new(app => $app);
$t->get_ok('/api/v1/products')->status_is(200)->json_has('/Products');

chdir "$FindBin::RealBin/..";
my $script = 'perl bin/jobgroups-cli';
my $cmd = qq{$script bump --host $host --target-host $host --match VERSION=16.0 --set VERSION=16.1 --no-dry-run --yes --no-delete-target 2>&1};
my $output = `$cmd`;
my $exit = $? >> 8;

is($exit, 0, 'CLI exited with code 0');

my $reqs = $t->get_ok('/__requests')->status_is(200)->tx->res->json;
ok(@$reqs >= 2, 'mock server saw at least two requests');

my ($update_req) = grep {
    ($_->{method} || '') =~ /^PUT|POST$/ && ($_->{path} || '') =~ m{^/api/v1/products}
} @$reqs;
ok($update_req, 'found POST/PUT to products');

my $final_ok = 0;
if ($update_req->{method} eq 'POST') {
    my $products2 = $t->get_ok('/api/v1/products')->status_is(200)->tx->res->json;
    for my $p (@{ $products2->{Products} }) {
        next unless $p->{settings};
        for my $s (@{ $p->{settings} }) {
            if ($s->{key} eq 'VERSION' && $s->{value} eq '16.1') {
                $final_ok = 1;
                last;
            }
        }
    }
}
else {
    if ($update_req->{path} =~ m{^/api/v1/products/([0-9]+)}) {
        my $id = $1;
        my $product = $t->get_ok("/api/v1/products/$id")->status_is(200)->tx->res->json;
        if ($product->{product} && $product->{product}{settings}) {
            for my $s (@{ $product->{product}{settings} }) {
                if ($s->{key} eq 'VERSION' && $s->{value} eq '16.1') {
                    $final_ok = 1;
                }
            }
        }
    }
}

ok($final_ok, 'VERSION setting updated to 16.1 in product settings');

done_testing();
