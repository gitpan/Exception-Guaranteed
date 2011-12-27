package __LabRat;

use warnings;
use strict;

sub spawn_n_kill (&) {
  my $cref = $_[1];
  {
    my $x = bless ( do { \$cref } );
    undef $x;
  }
  1;
}

sub DESTROY {
  ${$_[0]}->();
}

1;
