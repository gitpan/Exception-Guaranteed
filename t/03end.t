use warnings;
use strict;

use Test::More;
use Exception::Guaranteed;

use lib 't';
use __SelfDestruct;

my $dummy = 0;

my $err;
$SIG{__DIE__} = sub { $err = shift };

my $final_fn = __FILE__;
my $final_ln = __LINE__ + 1;
__SelfDestruct->spawn_n_kill( sub { guarantee_exception { die 'Final untrapped exception' } } );

while ($dummy < 2**31) {
  $dummy++;
}
fail ('Should never reach here :(');

END {
  diag( ($dummy||0) . " inc-ops executed before kill-signal delivery\n" );

  is (
    $err,
    "Final untrapped exception at $final_fn line $final_ln.\n",
    'Untrapped DESTROY exception correctly propagated',
  );

  # check, and then change $? set by the last die
  is ($?, 255, '$? correctly set by untrapped die()');   # $? in END{} is *NOT* 16bit

  $? = 0; # so test will pass
  done_testing;
}
