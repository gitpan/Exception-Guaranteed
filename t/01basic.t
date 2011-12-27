use warnings;
use strict;

use Test::More;
use Exception::Guaranteed;

use lib 't';
use __LabRat;

eval {
  guarantee_exception { die "Simple exception" }
};
like( $@, qr/^Simple exception/, 'A plain exception shoots through' );

my $fail = 0;
eval {
  guarantee_exception {
    __LabRat->spawn_n_kill(sub {
      die 'Exception outer';
    });
  };
  $fail = 1;
};
ok (!$fail, 'execution stopped after trappable destroy exception');
like( $@, qr/^Exception outer/, 'DESTROY exception thrown and caught from outside' );

$fail = 0;
# when using the fork+signal based approach, I can't make the exception
# happen fast enough to not shoot out of its real containing eval :(
# Hence the sleep
my $dummy = 0;
eval {
  __LabRat->spawn_n_kill( sub {
    guarantee_exception {
      die 'Exception inner';
    };
  });
  if (Exception::Guaranteed::BROKEN_SELF_SIGNAL) {
    while( $dummy < 2**31) {
      $dummy++;
    }
  }

  $fail = 1;  # we outh to never reach this
};

diag( ($dummy||0) . " inc-ops executed before kill-signal delivery\n" )
  if Exception::Guaranteed::BROKEN_SELF_SIGNAL;
ok (!$fail, 'execution stopped after trappable destroy exception');
like( $@, qr/^Exception inner/, 'DESTROY exception thrown and caught from inside of DESTROY block' );

done_testing;
