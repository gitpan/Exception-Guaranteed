package Exception::Guaranteed;

use warnings;
use strict;

our $VERSION = '0.00_01';
$VERSION = eval $VERSION if $VERSION =~ /_/;

use Config;
use Carp qw/croak cluck/;

use base 'Exporter';
our @EXPORT = ('guarantee_exception');
our @EXPORT_OK = ('guarantee_exception');

BEGIN {
  # older perls segfault if the cref behind the goto throws
  # Perl RT#35878
  *BROKEN_GOTO = ($] < 5.008_008_9) ? sub () { 1 } : sub () { 0 };

  # perls up until 5.12 (inclusive) seem to be happy with self-signaling
  # newer ones however segfault, so we resort to a killer sentinel fork
  *BROKEN_SELF_SIGNAL = ($] < 5.013) ? sub () { 0 } : sub () { 1 };
}

=head1 NAME

Exception::Guaranteed - Throw exceptions from anywhere - including DESTROY callbacks

=head1 DESCRIPTION

TODO

=cut

BEGIN {
  *__gen_killer_source = BROKEN_SELF_SIGNAL

    ? require POSIX && sub { sprintf <<'EOH', $_[0], $_[1] }
  my $killer_pid = fork();
  if (! defined $killer_pid) {
    die "Unable to fork ($!) while trying to guarantee the following exception:\n$err";
  }
  elsif (!$killer_pid) {
    kill (%d, %d);
    POSIX::_exit(0);
  }

EOH

    : sub { "kill( $_[0], $_[1] );" }
  ;
}

my $in_global_destroy;
END { $in_global_destroy = 1 }

# sig-to-number
my $sigs = do {
  my $s;
  for (split /\s/, $Config{sig_name}) {
    $s->{$_} = scalar keys %$s;
  }

  # we do not allow use of these signals
  delete @{$s}{qw/ZERO ALRM KILL SEGV CHLD/};
  $s;
};

my $guarantee_state = {};
sub guarantee_exception (&;@) {
  my ($cref, $signame) = @_;

  # use SIGABRT unless asked otherwise (available on all OSes afaict)
  $signame ||= 'ABRT';

  # because throwing any exceptions here is a delicate thing, we make the
  # exception text and then try real hard to throw when it's safest to do so
  my $sigwrong = do {sprintf
    "The requested signal '%s' is not valid on this system, use one of %s",
    $_[0],
    join ', ', map { "'$_'" } sort { $sigs->{$a} <=> $sigs->{$b} } keys %$sigs
  } if (! defined $sigs->{$signame} );

  croak $sigwrong if ( defined $^S and !$^S and $sigwrong );

  if (
    $in_global_destroy
      or
    $guarantee_state->{nested}
  ) {
    croak $sigwrong if $sigwrong;

    return $cref->() if BROKEN_GOTO;

    @_ = (); goto $cref;
  }

  local $guarantee_state->{nested} = 1;

  my (@result, $err);
  {
    local $@; # not sure this localization is necessary
    eval {
      croak $sigwrong if $sigwrong;

      {
        my $orig_sigwarn = $SIG{__WARN__} || sub { CORE::warn $_[0] };
        local $SIG{__WARN__} = sub { $orig_sigwarn->(@_) unless $_[0] =~ /^\t\Q(in cleanup)/ };

        my $orig_sigdie = $SIG{__DIE__} || sub {};
        local $SIG{__DIE__} = sub { ($err) = @_; $orig_sigdie->(@_) };

        if (!defined wantarray) {
          $cref->();
        }
        elsif (wantarray) {
          @result = $cref->();
        }
        else {
          $result[0] = $cref->();
        }
      }

      # a DESTROY-originating exception will not stop execution, but will still
      # land the error into $SIG{__DIE__} which places it in $err
      die $err if defined $err;

      1;
    } and return ( wantarray ? @result : $result[0] );  # return on successfull eval{}
  }

### if we got this far - the eval above failed
### just plain die if we can
  die $err unless __in_destroy_eval();

### we are in a destroy eval, can't just throw
### prepare the ninja-wizard exception guarantor
  if ($sigwrong) {
    cluck "Unable to set exception guarantor process - invalid signal '$signame' requested. Proceeding in undefined state...";
    die $err;
  }

  # non-localized, restorable from within the callback
  my $orig_handlers = {
    $signame => $SIG{$signame},
    BROKEN_SELF_SIGNAL ? ( CHLD => $SIG{CHLD} ) : (),
  };

  my $restore_sig_and_throw_callback = sub {
    for (keys %$orig_handlers) {
      if (defined $orig_handlers->{$_}) {
        $SIG{$_} = $orig_handlers->{$_};
      }
      else {
        delete $SIG{$_};
      }
    }
    die $err;
  };


  # use a string eval, minimize time spent in the handler
  my $sig_handler = $SIG{$signame} = eval( sprintf
    q|sub {
      if (__in_destroy_eval('in_sig')) {
        %s
      }
      else {
        $restore_sig_and_throw_callback->()
      }
    }|,
    __gen_killer_source($sigs->{$signame}, $$)
  ) or warn "Coderef fail!\n$@";

  # start the kill-loop
  $sig_handler->();
}

sub __in_destroy_eval {
  return 0 if (defined $^S and !$^S);

  my $f = ($_[0] ? 3 : 1);
  while (my $called_sub = (caller($f++))[3] ) {
    if ($called_sub eq '(eval)') {
      return 0;
    }
    elsif ($called_sub =~ /::DESTROY$/) {
      return 1;
    }
  }
  return 0;
}

=head1 AUTHOR

ribasushi: Peter Rabbitson <ribasushi@cpan.org>

=head1 CONTRIBUTORS

None as of yet

=head1 COPYRIGHT

Copyright (c) 2011 the Exception::Guaranteed L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself.

=cut

1;

1;
