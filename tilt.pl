#!/usr/bin/perl
###################################################################################
# Author: Ironton Brewing
#  -instagram: @ironton_brewing
#  -email: irontonbrewing@gmail.com
#
# Revision   Date       Comments
# Initial    11/28/23   Initial development
# 1.01       04/30/24   Use Tilt logo as window icon
#                       packPropagate to resize window as devices are added/removed
#                       minor bug fixes
#
# File: tilt.pl
# Purpose: Read low energy bluetooth iBeacon data from Tilt hydrometer devices.
#          Data is displayed in a Tk GUI and can be logged to a web end-point.
#          Options provided for calibration and data export as well.
#
# Reference:
#  Tilt hydrometer: https://tilthydrometer.com/
#  Tilt iBeacon data format: https://kvurd.com/blog/tilt-hydrometer-ibeacon-data-format/
#  Tilt iBeacon git python libraries: https://github.com/frawau/aioblescan  (not used here)
#
###################################################################################

use strict;
use warnings;
no warnings 'experimental::smartmatch';
use POSIX qw/mktime strftime/;
use Time::HiRes qw/time/;
use LWP::UserAgent;
use Tk;
use Tk::PNG;
use Tk::JPEG;

# turn on level 1 or 2 debug for troubleshooting
my $DEBUG = 0;

# GLOBALS
my ( %disp, %log, %cal, $logo, $tinyFont, $smallFont, $largeFont );

# the time in seconds with no updates from a Tilt before declaring it OFF and removing it from the program
my $TIMEOUT = 120;

# the UUID to match in an iBeacon packet for Tilt devices
my $id_regex = qr{A495BB([1-8])0C5B14B44B5121370F02D74DE};
my $time_regex = qr{ (\d{4}) - (\d{2}) - (\d{2}) \s (\d{2}) : (\d{2}) : (\d{2}) \. (\d+) }x;

my @names = qw(
  SEARCHING
  red
  green
  black
  purple
  orange
  blue
  yellow
  pink
);

# general background and font colors
my $bg = 'gray25';
my $fg = 'snow1';

# actual shades of color for the color color names
# default to the color itself, and override any shades below
# right now, only green needs to be changed?
my %colors;
map { $colors{$_} = $_ } @names;
$colors{'green'} = 'ForestGreen';
$colors{ $names[0] } = $bg;


# build the Tk MainWindow
my $mw = MainWindow->new( -title => 'Tilt Hydrometer' );
$mw->geometry('+100+100');
initGUI();

# read in initial config options
loadOpts();

# this is the main command for scanning/reading iBeacons (BT data)
# open a pipe for the command so it forks and continues to run in the background
# hci0 = built-in Bluetooth antenna
# hci1 = first additional antenna
# hcix = other antenna
my $bytes;
my $cmd = 'sudo hcitool -i hci0 lescan --duplicates | sudo hcidump -i hci0 -tR';
my $child = open BT, '-|', "$cmd";

# schedule a periodic read of BT data from the command pipe
# this should be very fast to avoid the handle from becoming filled and things getting behind
$mw->repeat( 5, \&readBeacon );

# check for the last recieved signal every half second
$mw->repeat( 500, \&lastHeard );

# periodic logger, to be started later
my $logger;


# start the Tk loop
MainLoop;


#===============================================
# Main methods (reading updates)
#===============================================

sub readBeacon {

  # read the next line of BT iBeacon data
  chomp( my $data = <BT> );

  # if this data starts with a '>' that indicates the beginning of a new message
  # thus, this is our indication to process the previous message
  if ( $data =~ s/^$time_regex >// && defined $bytes ) {

    # don't call mktime here to avoid creating timestamps for non-tilt iBeacons
    # this helps speed up the calls since this method is being triggered very rapidly
    my ($yr, $mon, $day, $hr, $min, $sec, $usec) = ($1, $2, $3, $4, $5, $6, $7);

    if ( $bytes =~ s/.*$id_regex// ) {
      my $name = $names[$1];

      addTilt($name) unless ( exists $disp{$name} );

      my $time = mktime( $sec, $min, $hr, $day, $mon - 1, $yr - 1900 ) + $usec / 1e6;
      updateTilt($name, $time, $bytes);
    }

    undef $bytes;  # reset byte stream
  }

  # if this looks like hex bytes add it to the data stream
  if ( $data =~ /^\s+([[:xdigit:]]{2}\s+?)+$/ ) {
    $data =~ s/\s+//g;  # remove whitespace
    $bytes .= $data;
  }
}


sub addTilt {
  my $name = shift;

  # shouldn't get this
  return if ( exists $disp{$name} );

  # get the actual color for this name
  my $color = $colors{$name};

  # delete any 'searching' notification, in case this is the first Tilt being added
  deleteTilt( $names[0] ) if ( exists $disp{ $names[0] } );

  my $frame = $mw->Frame( -bg => $bg,
                          -relief => 'groove',
                          -borderwidth => 3 );

  my ( $delta, $time, $timestamp, $sg, $sg_raw, $temp, $temp_raw, $rssi );
  $disp{$name} = { 'frame' => $frame,
                   'delta' => \$delta,
                   'timestamp' => \$timestamp,
                   'time'     => \$time,
                   'sg'       => \$sg,
                   'sg_raw'   => \$sg_raw,
                   'sg_label' => \my $sg_label,
                   'temp'     => \$temp,
                   'temp_raw' => \$temp_raw,
                   'temp_label' => \my $temp_label,
                   'rssi'     => \$rssi };

  my %entryOpts = (
    -state => 'readonly',
    -readonlybackground => $bg,
    -relief => 'flat',
    -justify => 'center',
    -highlightbackground => $bg,
    -fg => $fg
  );

  my %packOpts = (
    -side => 'top',
    -expand => 1,
    -fill => 'both'
  );

  # color indicator
  $frame->Label( -bg => $color,
                 -relief => 'raised',
                 -image => $logo,
                 -borderwidth => 1 )->pack(%packOpts);

  # specific gravity display
  $frame->Entry( -font => $smallFont,
                 -textvariable => \$sg_label,
                 %entryOpts )->pack(%packOpts);

  $frame->Entry( -font => $largeFont,
                 -textvariable => \$sg,
                 -width => 10,
                 %entryOpts )->pack(%packOpts);

  # temperature display
  $frame->Entry( -font => $smallFont,
                 -textvariable => \$temp_label,
                 %entryOpts )->pack(%packOpts);

  $frame->Entry( -font => $largeFont,
                 -textvariable => \$temp,
                 -width => 10,
                 %entryOpts )->pack(%packOpts);

  # last received display
  $frame->Entry( -font => $tinyFont,
                 -textvariable => \$delta,
                 -borderwidth => 0,
                 %entryOpts )->pack(%packOpts);

  # timestamp display
  $frame->Entry( -font => $tinyFont,
                 -textvariable => \$timestamp,
                 -borderwidth => 0,
                 %entryOpts )->pack(%packOpts);

  # Received signal strength indicator (RSSI) display
  $frame->Entry( -font => $tinyFont,
                 -textvariable => \$rssi,
                 -borderwidth => 0,
                 %entryOpts )->pack(%packOpts);

  # add the entire Tilt display box into the geometry manager last
  # this guarantees it will "see" the required room for the above widgets
  # determine the row/column to create a 3x3 grid (maximum)
  my $row = int( (scalar keys %disp) / 3 );
  my $col = (scalar keys %disp) - $row * 3;

  printf( "Adding %s Tilt in row $row col $col\n", uc($name) ) if ($DEBUG);
  $frame->grid( -row => $row, -column => $col );

  # update the menu options for this new color
  buildMenus();
}


sub updateTilt {
  my ($name, $time, $bytes) = @_;

  # reverse the byte order
  my @bytes = ( $bytes =~ m/../g );
  $bytes = join '', reverse @bytes;

  # in place of Tx power, Tilt actually reports weeks since battery change when converted to unsigned int
  my ($rssi, $batt, $sg, $temp) = unpack('cCS2', pack('H*', $bytes));
  undef $batt if ( unpack('c', pack('C', $batt) ) == -59 );

  # Tilt Pro reports an extra decimal of precision
  my $is_pro = $sg > 1500 ? 1 : 0;

  if ($is_pro) {
    $sg = sprintf( "%.4f", $sg / 10000 );
    $temp = sprintf( "%.1f", $temp / 10 );

  } else {
    $sg = sprintf( "%.3f", $sg / 1000 );
  }

  # apply any calibrations
  my $sg_raw = $sg;
  my $temp_raw = $temp;

  $sg += $cal{$name}{'sg'} if ( defined $cal{$name}{'sg'} && $cal{$name}{'sg'} ne '' );
  $temp += $cal{$name}{'temp'} if ( defined $cal{$name}{'temp'} && $cal{$name}{'temp'} ne '' );

  ${ $disp{$name}->{'sg_label'}  } = 'Specific gravity: ' . sprintf( $is_pro ? "%.04f" : "%.03f", $sg_raw ) . ' (uncal)';
  ${ $disp{$name}->{'sg'}        } = sprintf( $is_pro ? "%.04f" : "%.03f", $sg );
  ${ $disp{$name}->{'sg_raw'}    } = $sg_raw;

  ${ $disp{$name}->{'temp_label'}  } = 'Temperature: ' . $temp_raw . "\x{B0}F (uncal)";
  ${ $disp{$name}->{'temp'}        } = $temp . "\x{B0}F";
  ${ $disp{$name}->{'temp_raw'}    } = $temp_raw;

  ${ $disp{$name}->{'timestamp'} } = strftime( "%D %r", localtime($time) );
  ${ $disp{$name}->{'time'}      } = $time;
  ${ $disp{$name}->{'rssi'}      } = 'Signal: ' . $rssi . ' dBm';

  # add this data to the log data
  if ( defined $log{$name}{'timer'} ) {
    push @{ $log{$name}{'data'} }, { 'time' => $time, 'sg' => $sg, 'temp' => $temp, 'rssi' => $rssi };
  }

  if ($DEBUG > 2) {
    printf "%s Tilt @ %s\n", uc($name), strftime( "%D %r", localtime($time) );
    print "\tSG = $sg\n\ttemp = $temp degF\n\tRSSI = $rssi dBm";
    print "\n\tBattery is $batt weeks old" if ($batt);
    print "\n\n";
  }
}


sub lastHeard {
  foreach my $name (keys %disp) {

    if ( $name eq $names[0] ) {
      ${ $disp{$name}->{'timestamp'} } = strftime( "%D %r", localtime(time) );
      next;
    }

    my $delta = time - ${ $disp{$name}->{'time'} };

    if ( $delta > $TIMEOUT ) {
      deleteTilt($name);

    } else {
      ${ $disp{$name}->{'delta'} } = sprintf( "Received %.01f seconds ago", $delta );
    }
  }
}


sub deleteTilt {
  my $name = shift;

  return unless ( exists $disp{$name} );

  printf( "Deleting %s Tilt\n", uc($name) ) if ($DEBUG);

  $disp{$name}->{'frame'}->DESTROY;
  delete $disp{$name};
  buildMenus();

  if ( $name ne $names[0] ) {
    scalar keys %disp ? shiftLeft() : searching();
  }
}


sub shiftLeft {
  foreach my $name (keys %disp) {

    # determine the row/column to create a 3x3 grid (maximum)
    my $num = ( scalar keys %disp ) - 1;
    my $row = int( $num / 3 );
    my $col = $num - $row * 3;

    printf( "Shifting %s Tilt to row $row col $col\n", uc($name) ) if ($DEBUG);

    my $frame = $disp{$name}->{'frame'};
    $frame->gridForget;
    $frame->grid( -row => $row, -column => $col );
  }
}


sub initGUI {
  $mw->protocol( 'WM_DELETE_WINDOW', \&quit );
  $SIG{INT} = \&quit;

  $mw->packPropagate(1);

  # load the Tilt logo
  $logo = $mw->Photo( -file => './tilt_logo.png' );
  $mw->iconimage( $mw->Photo( -file => './tilt_icon.jpg' ) );

  # create some fonts
  $tinyFont  = $mw->fontCreate( 'tiny',  -family => 'Courier',   -size => 9,  -weight => 'bold' );
  $smallFont = $mw->fontCreate( 'small', -family => 'Helvetica', -size => 12 );
  $largeFont = $mw->fontCreate( 'large', -family => 'Helvetica', -size => 40, -weight => 'bold' );

  buildMenus();
  searching();
}


sub loadOpts {
  my $file = 'config.ini';
  return unless ( -e $file );
  open INI, "$file" or die "Could not open '$file' for reading: $!";

  my $name;
  my $name_regex = join "|", @names;
  $name_regex = qr{--($name_regex)}i;

  print "\nLoading configuration options:\n" if ($DEBUG > 1);

  while ( my $line = <INI> ) {
    chomp($line);

    next if ( $line =~ /^#/ );     # skip comment lines (beginning with #)
    next if ( $line eq '' );       # skip blank lines
    next if ( $line =~ /^\s+$/ );  # skip only whitespace lines

    if ( $line =~ $name_regex ) {
      $name = lc($1);
      next;
    }

    unless ( defined $name && $name ~~ @names ) {
      print "Error: invalid Tilt color '$name' for config options\n";
      next;
    }

    my ($opt, $value) = split /[;,=|]/, $line, 2;

    if ( $opt =~ /url/i ) {
      print "\tsetting $name log URL = $value\n" if ($DEBUG > 1);
      $log{$name}{'url'} = $value;

    } elsif ( $opt =~ /beer|name/i ) {
      print "\tsetting $name log beer = $value\n" if ($DEBUG > 1);
      $log{$name}{'beer'} = $value;

    } elsif ( $opt =~ /time|int(erval)|period/i ) {
      print "\tsetting $name log interval = $value\n" if ($DEBUG > 1);
      $log{$name}{'interval'} = $value;

    } elsif ( $opt =~ /sg/i ) {
      print "\tsetting $name cal SG = $value\n" if ($DEBUG > 1);
      $cal{$name}{'sg'} = $value;

    } elsif ( $opt =~ /temp/i ) {
      print "\tsetting $name cal temp = $value\n" if ($DEBUG > 1);
      $cal{$name}{'temp'} = $value;

    } else {
      print "Error: invalid option '$opt' for $name Tilt!\n";
    }
  }

  close INI;
  print "\n" if ($DEBUG > 1);
}


sub writeOpts {
  my $file = 'config.ini';
  open INI, ">$file" or die "Could not open '$file' for writing: $!";
  printf INI "# Tilt hydrometer configuration options\n" .
             "# written: %s\n\n", strftime( "%D %r", localtime(time) );

  my %opt_names;
  map { $opt_names{$_} = undef } ( keys %cal, keys %log );

  foreach my $name (keys %opt_names) {
    printf INI "--%s\n", uc($name);

    foreach my $key (qw/url beer interval/) {
      next unless ( defined $log{$name}{$key} );
      print INI "$key=$log{$name}{$key}\n";
    }

    foreach my $key (qw/sg temp/) {
      next unless ( defined $cal{$name}{$key} );
      print INI "$key=$cal{$name}{$key}\n";
    }

    print INI "\n";
  }

  close INI;
}


sub searching {
  printf( "Adding %s Tilt in row 0 col 0\n", uc( $names[0] ) ) if ($DEBUG);

  my $frame = $mw->Frame( -bg => $bg,
                          -relief => 'groove',
                          -borderwidth => 3 )->grid( -row => 0, -column => 0 );

  my $timestamp;
  $disp{ $names[0] } = { 'frame' => $frame,
                         'timestamp' => \$timestamp };

  $frame->Label( -bg => $bg,
                 -relief => 'flat',
                 -image => $logo,
                 -borderwidth => 1 )->pack( -side => 'left', -expand => 1, -fill => 'both' );

  $frame->Label( -text => 'Searching for Tilt...',
                 -font => $largeFont,
                 -bg => $bg,
                 -fg => $fg,
                 -relief => 'flat',
                 -borderwidth => 1 )->pack( -side => 'left', -expand => 1, -fill => 'both' );

  $frame->Entry( -font => $smallFont,
                 -textvariable => \$timestamp,
                 -state => 'readonly',
                 -readonlybackground => $bg,
                 -relief => 'flat',
                 -justify => 'center',
                 -highlightbackground => $bg,
                 -fg => $fg )->pack( -side => 'top' );

  lastHeard();
}


sub buildMenus {
  $mw->configure( -menu => my $menu = $mw->Menu );

  my $file = $menu->cascade( -label => 'File', -tearoff => 0 );
  my $export = $file->cascade( -label => 'Export data', -tearoff => 0 );
  $file->command( -label => 'Exit', -command => \&quit );

  my $config = $menu->cascade( -label => 'Configure', -tearoff => 0 );
  my $log = $config->cascade(  -label => 'Logging',   -tearoff => 0 );
  my $cal = $config->cascade(  -label => 'Calibrate', -tearoff => 0 );

  foreach my $m ($export, $cal, $log) {
    my $label = $m->cget(-label);
    my $cmd = $label =~ /export/i ? \&exportData :
              $label =~ /cal/i    ? \&calibrate  : \&logging;

    foreach my $name (keys %disp) {
      my $color = $colors{$name};

      my %menuOpts = (
        -label => uc($name),
        -bg => $color,
        -activebackground => $color,
        -foreground => $fg,
        -activeforeground => $fg
      );

      if ( $label =~ /export/i ) {
        $m->command( -command => [ $cmd, $name ], %menuOpts );

      } else {
        my $m2 = $m->cascade( %menuOpts, -tearoff => 0 );
        $m2->cget(-menu)->configure( -postcommand => [ $cmd, $m2, $name ] );
      }
    }
  }
}


#===============================================
# Logging methods
#===============================================

sub logging {
  my ($menu, $name) = @_;
  resetMenu($menu);

  $menu->command( -label => sprintf( "Setup Log (%s)", defined $log{$name}{'timer'} ? 'ACTIVE' : 'INACTIVE' ), -command => [ \&setupLog, $name ] );
  $menu->command( -label => 'Stop Log',  -command => [ \&stopLog,  $name ] );
}


sub setupLog {
  my $name = shift;

  my $log_frame = $mw->Toplevel( -title => sprintf( "%s Tilt log setup", uc($name) ) );

  $log_frame->Label( -text => 'URL: ' )->grid( -row => 0, -column => 0, -sticky => 'e' );
  $log_frame->Entry( -textvariable => \$log{$name}{'url'} )->grid( -row => 0, -column => 1 );

  $log_frame->Label( -text => 'Interval: ' )->grid( -row => 1, -column => 0, -sticky => 'e' );
  $log_frame->Entry( -textvariable => \$log{$name}{'interval'} )->grid( -row => 1, -column => 1 );

  $log_frame->Label( -text => 'Beer name: ' )->grid( -row => 2, -column => 0, -sticky => 'e' );
  $log_frame->Entry( -textvariable => \$log{$name}{'beer'} )->grid( -row => 2, -column => 1 );

  $log_frame->Button( -text => 'START',  -command => [ \&startLog, $log_frame, $name ] )->grid( -row => 3, -column => 0, -sticky => 'w' );
  $log_frame->Button( -text => 'CANCEL', -command => sub { $log_frame->DESTROY } )->grid( -row => 3, -column => 1, -sticky => 'e' );

  $log_frame->Label( -text => 'Status: ' )->grid( -row => 4, -column => 0, -columnspan => 2, -sticky => 'w' );
}


sub startLog {
  my ($log_frame, $name) = @_;

  return unless validateInterval(@_);

  $log_frame->DESTROY;

  my $interval = $log{$name}{'interval'} * 60 * 1000;
  $log{$name}{'timer'} = $mw->repeat( $interval, [ \&logPoint, $name ] );
  logPoint($name);
}


sub validateInterval {
  my ($log_frame, $name) = @_;

  my $int = $log{$name}{'interval'};

  if ( $int < 15 || $int > 60 ) {
    foreach my $w ( $log_frame->gridSlaves ) {
      if ( $w->isa('Tk::Label') && $w->cget(-text) =~ /status|error|warn/i ) {
        $w->configure( -text => 'Error: Log interval must be between 15-60 minutes!' );
        return 0;
      }
    }
  }

  return 1;
}


sub stopLog {
  my $name = shift;
  $log{$name}{'timer'}->cancel;
  $log{$name}{'timer'} = undef;
}


sub logPoint {
  my $name = shift;
  my $url = $log{$name}{'url'};

  my $req = HTTP::Request->new( 'POST', $url );
  $req->header( 'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8' );

  # get current time and convert to Excel time (1990 epoch)
  my $time = time;
  my $log_time = ($time / 86400) + 25569;
  my $last_logged = $log{$name}{'last_logged'} || $time;
  $log{$name}{'last_logged'} = $time;

  return 0 unless ( defined $log{$name}{'data'} );
  my @data = @{ $log{$name}{'data'} };
  my $num_data = scalar @data;
  return 0 unless $num_data;

  # if the last data point is prior to the time of the last log point
  # then no "new" data has been collected for this log point
  # theoretically, this should only happen when first starting a log
  if ( $data[-1]->{'time'} < $last_logged ) {
    print "No new data, not logging\n" if ($DEBUG);
    return 0;
  }

  # reset data for next interval
  # we don't want to save EVERY data point; that would be excessive
  $log{$name}{'data'} = undef;

  # calculate the average SG and temp over the previous time interval
  my ($sg_avg, $temp_avg, $rssi_avg);
  foreach my $data (@data) {
    next unless $data->{'time'} > $last_logged;
    $sg_avg += $data->{'sg'};
    $temp_avg += $data->{'temp'};
    $rssi_avg += $data->{'rssi'};
  }

  $sg_avg /= $num_data;
  $temp_avg /= $num_data;
  $rssi_avg /= $num_data;

  my $body = sprintf( "Timepoint=%f&" .
                      "Temp=%.01f&" .
                      "SG=%.04f&" .
                      "Beer=%s&" .
                      "Color=%s&" .
                      "Comment=%.01f", $log_time, $temp_avg, $sg_avg, $log{$name}{'beer'}, uc($name), $rssi_avg );

  $req->content($body);

  # first, add this data point to the internal log so we can export it later
  push @{ $log{$name}{'csv'} }, $body;

  if ($DEBUG) {
    printf( "Attempting to POST data point\n" .
           "\tTime: %s\n" .
           "\tAverage of $num_data points\n" .
           "\tHTML body: $body\n\n", strftime( "%D %r", localtime($time) ) );
  }

  my $lwp = LWP::UserAgent->new;
  my $resp = $lwp->request($req);

  unless ( $resp->is_success ) {
    printf( "Error logging data: %s\n", $resp->status_line );

  } elsif ($DEBUG) {
    printf( "LOG SUCCESS: %s\n", $resp->status_line );
  }
}


#===============================================
# Calibration methods
#===============================================

sub calibrate {
  my ($menu, $name) = @_;
  resetMenu($menu);

  $menu->command( -label => 'Calibrate SG in water',   -command => [ \&calibrateWater,  $name         ] );
  $menu->command( -label => 'Manual SG calibration',   -command => [ \&calibrateManual, $name, 'sg'   ] );
  $menu->command( -label => 'Manual temp calibration', -command => [ \&calibrateManual, $name, 'temp' ] );
}


sub calibrateWater {
  my $name = shift;
  my $sg_raw = ${ $disp{$name}{'sg_raw'} };
  $cal{$name}{'sg'} = ($sg_raw - 1) * -1;
}


sub calibrateManual {
  my ($name, $type) = @_;

  my $cal_frame = $mw->Toplevel( -title => sprintf( "%s manual %s calibration", uc($name), uc($type) ) );

  my $new_cal = $cal{$name}{$type};

  $cal_frame->Label( -text => sprintf( "%s offset: ", uc($type) ) )->grid( -row => 0, -column => 0, -sticky => 'e' );
  $cal_frame->Entry( -textvariable => \$new_cal )->grid( -row => 0, -column => 1 );

  $cal_frame->Button( -text => 'OK', -command => sub { $cal{$name}{$type} = $new_cal; $cal_frame->DESTROY } )->grid( -row => 1, -column => 0, -sticky => 'w' );
  $cal_frame->Button( -text => 'CANCEL', -command => sub { $cal_frame->DESTROY } )->grid( -row => 1, -column => 1, -sticky => 'e' );
}


#===============================================
# Log data export
#===============================================

sub exportData {
  my $name = shift;

  unless ( exists $log{$name}{'csv'} && scalar @{ $log{$name}{'csv'} } ) {
    printf "Error: no %s data to export!\n", uc($name);
    return;
  }

  my $file = $mw->getSaveFile( -title => sprintf( "%s Tilt Data Export", uc($name) ),
                               -defaultextension => '.csv',
                               -filetypes => [ ['CSV', '*.csv'] ],
                               -initialfile => "${name}_tilt_data" );

  unless ( defined $file && $file ne '' ) {
    print "Error: no file specified!\n";
    return;
  }

  open CSV, ">$file" or die "Could not open '$file' for writing: $!";

  my @data = @{ $log{$name}{'csv'} };

  my $header_done = 0;
  for my $i ( 0 .. $#data ) {
    my @parts = split /&/, $data[$i];

    my @line;
    foreach my $part (@parts) {
      my @d = split /=/, $part;
      push @line, $header_done ? $d[1] : $d[0];
    }

    my $line = join ",", @line;
    print CSV "$line\n";

    if (!$header_done) {
      $header_done = 1;
      $i--;
    }
  }

  close CSV;
}


#===============================================
# General methods
#===============================================

sub resetMenu {
  my $menu = shift;
  $menu->cget(-menu)->delete( 0, 'end' );
}


sub quit {
  kill 'HUP', $child if ($child);
  writeOpts();
  exit 0;
}

