package JobGroups::Command::bump;
use Mojo::Base 'OpenQA::CLI::api', -signatures;
use feature qw(say);
use Getopt::Long qw(GetOptionsFromArray);
use Mojo::URL;
use Data::Dumper;
use Module::Runtime qw(require_module);

has description => 'Manage products across openQA instances (match/set/create/delete)';
has usage => sub {
    "Usage: jobgroups-cli bump [--host HOST] [--apikey KEY] [--apisecret SECRET]\n"
      . "                      [--target-host [HOST]] [--target-apikey KEY] [--target-apisecret SECRET]\n"
      . "                      [--match key=value] [--set key=value] [--delete-target]\n"
      . "                      [--dry-run] [--no-dry-run --yes] [--retries N]\n\n"
      . "Examples:\n"
      . "  jobgroups-cli bump --host http://src --target-host http://tgt --match VERSION=16.0 --set VERSION=16.1\n\n"
      . "Defaults: dry-run (no writes). Pass --no-dry-run --yes to perform updates.\n";
};

sub _make_client_for_host ($self, $host, $apikey, $apisecret, $client_class) {
    $host = "http://$host" if $host && $host !~ m{^https?://};
    my $base_url = Mojo::URL->new($host // 'http://localhost');
    my $api_section = $base_url->host // 'localhost';
    $api_section .= ':' . $base_url->port if $base_url->port && $base_url->port !~ /^(?:80|443)$/;

    $client_class //= 'OpenQA::Client';
    eval { require_module($client_class); 1 } or die "Cannot load client class $client_class: $@";

    my %client_args = ( api => $api_section );
    $client_args{apikey}    = $apikey    if defined $apikey;
    $client_args{apisecret} = $apisecret if defined $apisecret;

    my $c = $client_class->new(%client_args);
    $c->ioloop(Mojo::IOLoop->singleton) if $c->can('ioloop');
    $c->base_url($base_url) if $c->can('base_url');
    $c->transactor->name('jobgroups-cli') if $c->can('transactor');

    return $c;
}

sub _product_matches ($self, $product, $match_criteria) {
    for my $k (keys %$match_criteria) {
        my $want = $match_criteria->{$k};
        if (exists $product->{$k} && !ref $product->{$k}) {
            return 0 unless defined $product->{$k} && $product->{$k} eq $want;
            next;
        }
        my $found = 0;
        for my $container (qw(settings variables attributes)) {
            if (ref $product->{$container} eq 'HASH' && exists $product->{$container}{$k}) {
                if (defined $product->{$container}{$k} && $product->{$container}{$k} eq $want) {
                    $found = 1; last;
                }
            }
        }
        return 0 unless $found;
    }
    return 1;
}

sub _apply_set_criteria ($self, $product, $set_criteria) {
    my $changes = 0;
    for my $k (keys %$set_criteria) {
        my $val = $set_criteria->{$k};
        my $placed = 0;
        for my $container (qw(settings variables attributes)) {
            if (ref $product->{$container} eq 'HASH' && exists $product->{$container}{$k}) {
                $product->{$container}{$k} = $val; $placed = 1; last;
            }
        }
        unless ($placed) {
            $product->{settings} = {} unless ref $product->{settings} eq 'HASH';
            $product->{settings}{$k} = $val;
        }
        $changes++;
    }
    return $changes;
}

sub run ($self, @args) {
    my %opts = (
        host              => undef,
        apikey            => undef,
        apisecret         => undef,
        'target-host'     => undef,
        'target-apikey'   => undef,
        'target-apisecret'=> undef,
        match             => [],
        set               => [],
        'delete-target'   => 0,
        dry_run           => 1,
        yes               => 0,
        retries           => undef,
        verbose           => 0,
        quiet             => 0,
        pretty            => 0,
        links             => 0,
    );

    GetOptionsFromArray(
        \@args,
        'host=s'               => \$opts{host},
        'apikey=s'             => \$opts{apikey},
        'apisecret=s'          => \$opts{apisecret},
        'target-host:s'        => \$opts{'target-host'},
        'target-apikey=s'      => \$opts{'target-apikey'},
        'target-apisecret=s'   => \$opts{'target-apisecret'},
        'match=s@'             => \$opts{match},
        'set=s@'               => \$opts{set},
        'delete-target!'       => \$opts{'delete-target'},
        'dry-run!'             => \$opts{dry_run},
        'yes|y'                => \$opts{yes},
        'retries=i'            => \$opts{retries},
        'verbose!'             => \$opts{verbose},
        'quiet!'               => \$opts{quiet},
        'pretty!'              => \$opts{pretty},
        'links!'               => \$opts{links},
    ) or die $self->usage;

    # forward global-style options to parent helpers
    $self->options({ verbose => $opts{verbose}, quiet => $opts{quiet}, pretty => $opts{pretty}, links => $opts{links} });

    # detect bare --target-host presence
    my $target_host_flag_present = !!grep { $_ eq '--target-host' || /^--target-host=/ } @args;

    if ($target_host_flag_present && (!defined $opts{'target-host'} || $opts{'target-host'} eq '')) {
        $opts{'target-host'} = 'http://localhost';
    }

    my $src_host = $opts{host} // $ENV{OPENQA_HOST} // 'http://localhost';
    $src_host = "http://$src_host" if $src_host !~ m{^https?://};

    $self->apikey($opts{apikey})    if defined $opts{apikey};
    $self->apisecret($opts{apisecret}) if defined $opts{apisecret};

    say "Source host: $src_host";
    say "Dry run mode (no writes) enabled" if $opts{dry_run} && !$opts{yes};

    # create src client
    my $src_client = $self->client(Mojo::URL->new($src_host));
    my $products_url = Mojo::URL->new('/api/v1/products')->to_abs($src_client->base_url);

    my $tx = $src_client->build_tx(GET => $products_url);
    my $rc = $self->retry_tx($src_client, $tx, $opts{retries});
    return $rc if $rc != 0;

    my $json = $tx->res->json // {};
    my $products = $json->{products} // $json->{Products} // $json;
    $products = [$products] unless ref $products eq 'ARRAY';

    my %match_criteria;
    for my $m (@{$opts{match}}) { $match_criteria{$1} = $2 if $m =~ /^([^=]+)=(.*)$/s }
    my %set_criteria;
    for my $s (@{$opts{set}}) { $set_criteria{$1} = $2 if $s =~ /^([^=]+)=(.*)$/s }

    my $tgt_host = defined $opts{'target-host'} ? $opts{'target-host'} : $src_host;
    my $tgt_client;
    if ($tgt_host eq $src_host && !defined $opts{'target-apikey'} && !defined $opts{'target-apisecret'}) {
        $tgt_client = $src_client;
        say "Target is same as source: " . $tgt_client->base_url->to_string;
    }
    else {
        $tgt_client = $self->_make_client_for_host($tgt_host, $opts{'target-apikey'}, $opts{'target-apisecret'});
        say "Target host: " . $tgt_client->base_url->to_string;
    }

    my @candidates = grep { $self->_product_matches($_, \%match_criteria) } @$products;
    say scalar(@candidates) . " product(s) matched criteria";

    my @created_on_target;
    for my $p (@candidates) {
        debug("Source product:", $p) if $self->options->{verbose};
        my $new = $p; # user requested no deep-clone for JSON payloads
        delete $new->{id}; delete $new->{product_id} if exists $new->{product_id};

        my $changed = $self->_apply_set_criteria($new, \%set_criteria);
        say "Prepared new product (changes applied: $changed)";

        debug("New product payload:", $new) if $self->options->{verbose};

        if (!$opts{dry_run} && $opts{yes}) {
            my $create_url = Mojo::URL->new('/api/v1/products')->to_abs($tgt_client->base_url);
            say "Creating product on target: $create_url";
            my $tx2 = $tgt_client->build_tx(POST => $create_url => json => $new);
            my $rc2 = $self->retry_tx($tgt_client, $tx2, $opts{retries});
            if ($rc2 == 0) {
                my $res2 = $tx2->res;
                my $created = $res2->json // {};
                push @created_on_target, $created;
                say "Product created on target (response): " . Dumper($created);
            }
            else {
                warn "Failed to create product on target (rc=$rc2)\n";
            }
        }
        else {
            say "Dry run: would create product on target (use --no-dry-run --yes to apply)";
        }
    }

    if ($opts{'delete-target'} && @created_on_target) {
        for my $created (@created_on_target) {
            my $tid = $created->{id} // $created->{product_id} // $created->{_id};
            unless ($tid) { warn "Cannot delete created product - no id present in response: " . Dumper($created); next }
            my $del_url = Mojo::URL->new("/api/v1/products/$tid")->to_abs($tgt_client->base_url);
            say "Deleting created product on target: $del_url";
            if (!$opts{dry_run} && $opts{yes}) {
                my $txd = $tgt_client->build_tx(DELETE => $del_url);
                my $rcd = $self->retry_tx($tgt_client, $txd, $opts{retries});
                if ($rcd == 0) { say "Deleted target product $tid" }
                else { warn "Failed to delete target product $tid (rc=$rcd)\n" }
            }
            else { say "Dry run: would delete target product $tid" }
        }
    }

    return 0;
}

1;
