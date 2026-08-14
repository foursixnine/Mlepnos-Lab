use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::RealBin/../t/lib";

use MockOpenQA qw(start_mock_server stop_mock_server mock_base_url req_file_path);
use Mojo::JSON qw(decode_json);
use OpenQA::Client;

# Start mock server
my ($pid, $port, $req_file) = start_mock_server();
ok($pid, 'mock server started');

my $host = "127.0.0.1:$port";

# Run the CLI as requested
chdir "$FindBin::RealBin/..";    # into openSUSE/openQA/Helpers/openqa-job-settings

my $script = "perl bin/jobgroups-cli";
my $cmd = qq{$script bump --host $host --target-host $host --match VERSION=16.0 --set VERSION=16.1 --no-dry-run --yes --no-delete-target 2>&1};
my $output = `$cmd`;
my $exit   = $? >> 8;

is($exit, 0, "CLI exited with code 0");

# Build client to query mock server
my $url = OpenQA::Client::url_from_host($host);
my $client = OpenQA::Client->new(api => $url->host);

# First fetch list of products the CLI would have queried
my $products_url = $url->clone->path('/api/v1/products');
my $res = $client->get($products_url)->res;
ok($res && $res->is_success, 'fetched products list');
my $products = decode_json($res->body || '[]');

ok(ref $products eq 'HASH' && $products->{Products}, 'products structure present');

# Now fetch recorded requests for assertion
my $reqs_url = $url->clone->path('/__requests');
my $reqs_res = $client->get($reqs_url)->res;
ok($reqs_res && $reqs_res->is_success, 'fetched recorded requests');
my $reqs = decode_json($reqs_res->body || '[]');

ok(@$reqs >= 2, 'mock server saw at least two requests');

# Look for a PUT or POST to /api/v1/products or /api/v1/products/:id
my ($put_req) = grep { ($_->{method} || '') =~ /^PUT|POST$/ && ($_->{path} || '') =~ m{^/api/v1/products} } @$reqs;
ok($put_req, 'found POST/PUT to products');

# Extract the id used (either returned by POST or used in PUT)
# If POST was used, mock server returns id and the script should then GET it; test final state by GET id
my $final_ok = 0;
if ($put_req->{method} eq 'POST') {
    # parse POST response id by fetching products list again and finding a product with settings VERSION=16.1
    my $res2 = $client->get($products_url)->res;
    ok($res2 && $res2->is_success, 'fetched products list after POST');
    my $products2 = decode_json($res2->body || '[]');
    for my $p (@{$products2->{Products}}) {
        if ($p->{settings}) {
            for my $s (@{$p->{settings}}) {
                if ($s->{key} eq 'VERSION' && $s->{value} eq '16.1') {
                    $final_ok = 1;
                    last;
                }
            }
        }
    }
}
else {
    # PUT case: get the id from path and fetch product by id
    if ($put_req->{path} =~ m{^/api/v1/products/([0-9]+)}) {
        my $id = $1;
        my $product_url = $url->clone->path("/api/v1/products/$id");
        my $prod_res = $client->get($product_url)->res;
        ok($prod_res && $prod_res->is_success, 'fetched product by id');
        my $prod = decode_json($prod_res->body || '{}');
        if ($prod->{product} && $prod->{product}{settings}) {
            for my $s (@{$prod->{product}{settings}}) {
                if ($s->{key} eq 'VERSION' && $s->{value} eq '16.1') {
                    $final_ok = 1;
                }
            }
        }
    }
}

ok($final_ok, 'VERSION setting updated to 16.1 in product settings');

# Stop mock server
stop_mock_server();

done_testing();
