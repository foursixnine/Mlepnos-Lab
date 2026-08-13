use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/../t/lib";

use JobGroups::Command::bump;

# Basic dry-run smoke test
my $cmd = JobGroups::Command::bump->new;
my $rc = $cmd->run('--host', 'http://example.com');
ok($rc == 0, 'dry-run returns 0');

done_testing();
