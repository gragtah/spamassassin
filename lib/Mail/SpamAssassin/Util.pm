# A general class for utility functions.  Please use this for
# functions that stand alone, without requiring a $self object,
# Portability functions especially.

# Copyright (C) 2003  Justin Mason
# Copyright (C) 2003  Daniel Quinlan
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of either the Artistic License or the GNU General
# Public License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.

package Mail::SpamAssassin::Util;

use strict;
use bytes;

use vars qw (
  @ISA @EXPORT
  $AM_TAINTED $HOSTNAME $FQHOSTNAME
);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(local_tz);

use Mail::SpamAssassin;
use File::Spec;
use Time::Local;
use Sys::Hostname;

BEGIN { $HOSTNAME = hostname(); }

use constant RUNNING_ON_WINDOWS => ($^O =~ /^(?:mswin|dos|os2)/oi);

###########################################################################

# find an executable in the current $PATH (or whatever for that platform)
{
  # Show the PATH we're going to explore only once.
  my $displayed_path = 0;

  sub find_executable_in_env_path {
    my ($filename) = @_;

    clean_path_in_taint_mode();
    if ( !$displayed_path++ ) {
      dbg("Current PATH is: ".join(":",File::Spec->path()));
    }
    foreach my $path (File::Spec->path()) {
      my $fname = File::Spec->catfile ($path, $filename);
      if ( -f $fname ) {
        if (-x $fname) {
          dbg ("executable for $filename was found at $fname");
          return $fname;
        }
        else {
          dbg("$filename was found at $fname, but isn't executable");
        }
      }
    }
    return undef;
  }
}

###########################################################################

# taint mode: delete more unsafe vars for exec, as per perlsec
{
  # We only need to clean the environment once, it stays clean ...
  my $cleaned_taint_path = 0;

  sub clean_path_in_taint_mode {
    return if ( $cleaned_taint_path++ );
    return unless am_running_in_taint_mode();

    dbg("Running in taint mode, removing unsafe env vars, and resetting PATH");

    delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
    $ENV{'PATH'} = '/bin:/usr/bin:/usr/local/bin';
  }
}

# taint mode: are we running in taint mode? 1 for yes, undef for no.
sub am_running_in_taint_mode {
  if (defined $AM_TAINTED) { return $AM_TAINTED; }
  
  my $blank = substr ($ENV{PATH}, 0, 0);
  $AM_TAINTED = not eval { eval "1 || $blank" || 1 };
  dbg ("running in taint mode? ".($AM_TAINTED?"yes":"no"));
  return $AM_TAINTED;
}

###########################################################################

sub am_running_on_windows {
  return RUNNING_ON_WINDOWS;
}

###########################################################################

# untaint a path to a file, e.g. "/home/jm/.spamassassin/foo",
# "C:\Program Files\SpamAssassin\tmp\foo", "/home/��t/etc".
#
# TODO: this does *not* handle locales well.  We cannot use "use locale"
# and \w, since that will not detaint the data.  So instead just allow the
# high-bit chars from ISO-8859-1, none of which have special metachar
# meanings (as far as I know).
#
sub untaint_file_path {
  my ($path) = @_;

  return unless defined($path);
  return '' if ($path eq '');

  # Barry Jaspan: allow ~ and spaces, good for Windows.  Also return ''
  # if input is '', as it is a safe path.
  my $chars = '-_A-Za-z\xA0-\xFF0-9\.\@\=\+\,\/\\\:';
  my $re = qr/^\s*([$chars][${chars}~ ]*)$/o;

  if ($path =~ $re) {
    return $1;
  } else {
    warn "security: cannot untaint path: \"$path\"\n";
    return $path;
  }
}

# This sub takes a scalar or a reference to an array, hash, scalar or another
# reference and recursively untaints all its values (and keys if it's a
# reference to a hash). It should be used with caution as blindly untainting
# values subverts the purpose of working in taint mode. It will return the
# untainted value if requested but to avoid unnecessary copying, the return
# value should be ignored when working on lists.
# Bad:
#  %ENV = untaint_var(\%ENV);
# Better:
#  untaint_var(\%ENV);
#
sub untaint_var {
  local ($_) = @_;

  unless (ref) {
    /^(.*)$/;
    return $1;
  }
  elsif (ref eq 'ARRAY') {
    @{$_} = map { $_ = untaint_var($_) } @{$_};
    return @{$_} if wantarray;
  }
  elsif (ref eq 'HASH') {
    foreach my $k (keys %{$_}) {
      ${$_}{untaint_var($k)} = untaint_var(${$_}{$k});
    }
    return %{$_} if wantarray;
  }
  elsif (ref eq 'SCALAR' or ref eq 'REF') {
    ${$_} = untaint_var(${$_});
  }
  else {
    warn "Can't untaint a " . ref($_) . "!\n";
  }
  return $_;
}

###########################################################################

# timezone mappings: in case of conflicts, use RFC 2822, then most
# common and least conflicting mapping
my %TZ = (
	# standard
	'UT'   => '+0000',
	'UTC'  => '+0000',
	# US and Canada
	'AST'  => '-0400',
	'ADT'  => '-0300',
	'EST'  => '-0500',
	'EDT'  => '-0400',
	'CST'  => '-0600',
	'CDT'  => '-0500',
	'MST'  => '-0700',
	'MDT'  => '-0600',
	'PST'  => '-0800',
	'PDT'  => '-0700',
	'HST'  => '-1000',
	'AKST' => '-0900',
	'AKDT' => '-0800',
	# European
	'GMT'  => '+0000',
	'BST'  => '+0100',
	'IST'  => '+0100',
	'WET'  => '+0000',
	'WEST' => '+0100',
	'CET'  => '+0100',
	'CEST' => '+0200',
	'EET'  => '+0200',
	'EEST' => '+0300',
	'MSK'  => '+0300',
	'MSD'  => '+0400',
	# Australian
	'AEST' => '+1000',
	'AEDT' => '+1100',
	'ACST' => '+0930',
	'ACDT' => '+1030',
	'AWST' => '+0800',
	);

# month mappings
my %MONTH = (jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6,
	     jul => 7, aug => 8, sep => 9, oct => 10, nov => 11, dec => 12);

sub local_tz {
  # standard method for determining local timezone
  my $time = time;
  my @g = gmtime($time);
  my @t = localtime($time);
  my $z = $t[1]-$g[1]+($t[2]-$g[2])*60+($t[7]-$g[7])*1440+($t[5]-$g[5])*525600;
  return sprintf("%+.2d%.2d", $z/60, $z%60);
}

sub parse_rfc822_date {
  my ($date) = @_;
  local ($_);
  my ($yyyy, $mmm, $dd, $hh, $mm, $ss, $mon, $tzoff);

  # make it a bit easier to match
  $_ = " $date "; s/, */ /gs; s/\s+/ /gs;

  # now match it in parts.  Date part first:
  if (s/ (\d+) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) / /i) {
    $dd = $1; $mon = lc($2); $yyyy = $3;
  } elsif (s/ (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) +(\d+) \d+:\d+:\d+ (\d{4}) / /i) {
    $dd = $2; $mon = lc($1); $yyyy = $3;
  } elsif (s/ (\d+) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{2,3}) / /i) {
    $dd = $1; $mon = lc($2); $yyyy = $3;
  } else {
    dbg ("time cannot be parsed: $date");
    return undef;
  }

  # handle two and three digit dates as specified by RFC 2822
  if (defined $yyyy) {
    if (length($yyyy) == 2 && $yyyy < 50) {
      $yyyy += 2000;
    }
    elsif (length($yyyy) != 4) {
      # three digit years and two digit years with values between 50 and 99
      $yyyy += 1900;
    }
  }

  # hh:mm:ss
  if (s/ (\d?\d):(\d\d)(:(\d\d))? / /) {
    $hh = $1; $mm = $2; $ss = $4 || 0;
  }

  # numeric timezones
  if (s/ ([-+]\d{4}) / /) {
    $tzoff = $1;
  }
  # UT, GMT, and North American timezones
  elsif (s/\b([A-Z]{2,4})\b/ / && exists $TZ{$1}) {
    $tzoff = $TZ{$1};
  }
  # all other timezones are considered equivalent to "-0000"
  $tzoff ||= '-0000';

  # months
  if (exists $MONTH{$mon}) {
    $mmm = $MONTH{$mon};
  }

  $hh ||= 0; $mm ||= 0; $ss ||= 0; $dd ||= 0; $mmm ||= 0; $yyyy ||= 0;

  my $time;
  eval {		# could croak
    $time = timegm ($ss, $mm, $hh, $dd, $mmm-1, $yyyy);
  };

  if ($@) {
    dbg ("time cannot be parsed: $date, $yyyy-$mmm-$dd $hh:$mm:$ss");
    return undef;
  }

  if ($tzoff =~ /([-+])(\d\d)(\d\d)$/)	# convert to seconds difference
  {
    $tzoff = (($2 * 60) + $3) * 60;
    if ($1 eq '-') {
      $time += $tzoff;
    } else {
      $time -= $tzoff;
    }
  }

  return $time;
}

###########################################################################

sub portable_getpwuid {
  if (defined &Mail::SpamAssassin::Util::_getpwuid_wrapper) {
    return Mail::SpamAssassin::Util::_getpwuid_wrapper(@_);
  }

  if (!RUNNING_ON_WINDOWS) {
    eval ' sub _getpwuid_wrapper { getpwuid($_[0]); } ';
  } else {
    dbg ("defining getpwuid() wrapper using 'unknown' as username");
    eval ' sub _getpwuid_wrapper { fake_getpwuid($_[0]); } ';
  }

  if ($@) {
    warn "Failed to define getpwuid() wrapper: $@\n";
  } else {
    return Mail::SpamAssassin::Util::_getpwuid_wrapper(@_);
  }
}

sub fake_getpwuid {
  return (
    'unknown',		# name,
    'x',		# passwd,
    $_[0],		# uid,
    0,			# gid,
    '',			# quota,
    '',			# comment,
    '',			# gcos,
    '/',		# dir,
    '',			# shell,
    '',			# expire
  );
}

###########################################################################

# Given a string, extract an IPv4 address from it.  Required, since
# we currently have no way to portably unmarshal an IPv4 address from
# an IPv6 one without kludging elsewhere.
#
sub extract_ipv4_addr_from_string {
  my ($str) = @_;

  return unless defined($str);

  if ($str =~ /\b(
			(?:1\d\d|2[0-4]\d|25[0-5]|\d\d|\d)\.
			(?:1\d\d|2[0-4]\d|25[0-5]|\d\d|\d)\.
			(?:1\d\d|2[0-4]\d|25[0-5]|\d\d|\d)\.
			(?:1\d\d|2[0-4]\d|25[0-5]|\d\d|\d)
		      )\b/ix)
  {
    if (defined $1) { return $1; }
  }

  # ignore native IPv6 addresses; currently we have no way to deal with
  # these if we could extract them, as the DNSBLs don't provide a way
  # to query them!  TODO, eventually, once IPv6 spam starts to appear ;)
  return;
}

###########################################################################
# get the current host's fully-qualified domain name, if possible.  If
# not possible, return the unqualified hostname.

sub fq_hostname {
  if (defined $FQHOSTNAME) { return $FQHOSTNAME; }

  my $hname = $HOSTNAME;
  if ($hname !~ /\./) {
    my @names = grep(/^\Q${hname}\E\./o,
				map { split } (gethostbyname($hname))[0 .. 1]);
    $hname = $names[0] if (scalar @names > 0);
  }

  $FQHOSTNAME = $hname;
  return $FQHOSTNAME;
}

###########################################################################

sub my_inet_aton { unpack("N", pack("C4", split(/\./, $_[0]))) }

###########################################################################

sub dbg { Mail::SpamAssassin::dbg (@_); }

1;
