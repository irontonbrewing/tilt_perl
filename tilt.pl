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
# 1.1        02/03/25   Move bluetooth packet reading to separate thread
#                       Google sheets support
#                       Better dynamic dimensioning of GUI/widgets
#                       Event and beacon data logs
#                       Verbose switch at command line
#                       Log state on Tilt display
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

# packages
use strict;
use warnings;
no warnings 'experimental::smartmatch';

use Carp;
use POSIX qw/mktime strftime/;
use Time::HiRes qw/time/;
use Getopt::Long;
use LWP::UserAgent;
use URI;
use JSON;

use Tk;
use Tk::PNG;
use Tk::JPEG;

use threads;
use Thread::Queue;

# GLOBALS
my ( %disp, %log, %cal, $logo, $tinyFont, $smallFont, $largeFont, $logFont );
my ( $eventWindow, $eventScrolled, @eventHistory,  );
my ( $beaconWindow, $beaconScrolled );

# default setting to auto-scroll the event/beacon logs
my $eventAutoScroll = 1;
my $beaconAutoScroll = 1;

# determine verbose mode
my $VERBOSE = 0;
GetOptions( 'v|verbose+' => \$VERBOSE );

# the time in seconds with no updates from a Tilt before declaring it OFF and removing it from the program
my $TIMEOUT = 120;

# default to minimum log interval
my $MIN_LOG_TIME = 15;  # minutes
my $MAX_LOG_TIME = 60;

# periodic logger, to be started later
my $logger;

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

# general background colors
my $bg = 'gray25';
my $fg = 'snow1';

# actual shades of color for the color names
# default to the color itself, and override any shades below
# right now, only green needs to be changed?
my %colors;
map { $colors{$_} = $_ } @names;
$colors{'green'} = 'ForestGreen';
$colors{ $names[0] } = $bg;

# global queue for passing complete beacon messages from the reading thread to the main thread
my $btQueue = Thread::Queue->new();

# build the Tk MainWindow
my $mw = MainWindow->new( -title => 'Tilt Hydrometer' );
$mw->geometry('+100+100');
initGUI();

# read in initial config options
loadOpts();

# start the BT scanning in a separate thread
my $bt_thread = threads->create( \&readBeacon );

# poll the BT queue every 50ms
$mw->repeat( 50, \&processBeacon );

# check for the last recieved signal every half second
$mw->repeat( 500, \&lastHeard );

# start the Tk loop
MainLoop;


#===============================================
# Main methods (reading updates)
#===============================================

sub readBeacon {

  # this is the main command for scanning/reading iBeacons (BT data)
  # hci0 = built-in Bluetooth antenna
  # hci1 = first additional antenna
  # hcix = other antenna

  my $cmd = 'sudo hcitool -i hci0 lescan --duplicates | sudo hcidump -i hci0 -tR';
  open(my $BT, '-|', $cmd) or die "Cannot run '$cmd': $!";

  my $bytes;  # accumulator for hex bytes

  # read the next line of BT iBeacon data
  while (my $data = <$BT>) {
    chomp $data;

    # if this data starts with a '>' that indicates the beginning of a new message
    # thus, this is our indication to process the previous message
    if ( $data =~ s/^$time_regex >// && defined $bytes ) {

      # Enqueue a hash reference with the collected data
      # don't call mktime here to avoid creating timestamps for non-tilt iBeacons
      # this helps speed up the calls since this method is being triggered very rapidly
      $btQueue->enqueue({
        yr    => $1,
        mon   => $2,
        day   => $3,
        hr    => $4,
        min   => $5,
        sec   => $6,
        usec  => $7,
        'bytes' => $bytes,
      });

      undef $bytes;  # reset byte stream
    }

    # if this looks like hex bytes add it to the data stream
    if ( $data =~ /^\s+([[:xdigit:]]{2}\s+?)+$/ ) {
      $data =~ s/\s+//g;  # remove whitespace
      $bytes .= $data;
    }
  }

  close $BT;
}


sub processBeacon {

  # process all messages currently in the queue
  while ( my $msg = $btQueue->dequeue_nb() ) {

    my $bytes = $msg->{'bytes'};

    # see if this message belongs to a Tilt device
    if ( $bytes =~ s/.*$id_regex// ) {
      my $name = $names[$1];

      # add a new Tilt display if one doesn’t already exist
      addTilt($name) unless ( exists $disp{$name} );

      # create a timestamp
      my $time = mktime( $msg->{sec},
                         $msg->{min},
                         $msg->{hr},
                         $msg->{day},
                         $msg->{mon} - 1,
                         $msg->{yr} - 1900 ) + $msg->{usec} / 1e6;

      warn "Could not create timestamp for $name beacon" unless ( defined $time );

      # process the beacon data
      updateTilt($name, $time, $bytes);
    }
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

  my ( $delta, $time, $timestamp, $sg, $sg_raw, $temp, $temp_raw, $rssi_label, $log_state );
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
                   'temp_val'   => \my $temp_val,
                   'rssi_label' => \$rssi_label,
                   'rssi'       => \my $rssi,
                   'log_state'  => \$log_state };

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
                 -textvariable => \$rssi_label,
                 -borderwidth => 0,
                 %entryOpts )->pack(%packOpts);

  # indicator for logging status
  $frame->Entry( -font => $tinyFont,
                 -textvariable => \$log_state,
                 -borderwidth => 0,
                 %entryOpts )->pack(%packOpts);

  # add the entire Tilt display box into the geometry manager last
  # this guarantees it will "see" the required room for the above widgets
  # determine the row/column to create a 3x3 grid (maximum)
  my $row = int( (scalar keys %disp) / 3 );
  my $col = (scalar keys %disp) - $row * 3;

  eventLog( sprintf( "Adding %s Tilt in row $row, col $col", uc($name) ) );
  $frame->grid( -row => $row, -column => $col );

  logState($name);  # update the log state on initialization

  # update the menu options for this new color
  buildMenus();

  # force the GUI to resize to accommodate the new Tilt
  sizeGUI();
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

  ${ $disp{$name}->{'temp_label'} } = 'Temperature: ' . $temp_raw . "\x{B0}F (uncal)";
  ${ $disp{$name}->{'temp'}       } = $temp . "\x{B0}F";
  ${ $disp{$name}->{'temp_raw'}   } = $temp_raw;
  ${ $disp{$name}->{'temp_val'}   } = $temp;

  ${ $disp{$name}->{'timestamp'} } = strftime( "%D %r", localtime($time) );
  ${ $disp{$name}->{'time'}      } = $time;
  ${ $disp{$name}->{'rssi_label'} } = 'Signal: ' . $rssi . ' dBm';
  ${ $disp{$name}->{'rssi'} } = $rssi;

  # add this data to the log data
  if ( defined $log{$name}{'timer'} ) {
    push @{ $log{$name}{'data'} }, { 'time' => $time, 'sg' => $sg, 'temp' => $temp, 'rssi' => $rssi };
  }

  my $beacon = sprintf( "%s Tilt beacon", uc($name) );
    $beacon .= "\nSG: $sg";
    $beacon .= "\nTemp: $temp degF";
    $beacon .= "\nRSSI: $rssi dBm";
    $beacon .= "\nBattery: $batt weeks old" if ($batt);
    $beacon .= "\nRaw data: $bytes";
  beaconLog($beacon);
}


sub lastHeard {
  foreach my $name (keys %disp) {

    if ( $name eq $names[0] ) {
      ${ $disp{$name}->{'timestamp'} } = strftime( "%D %r", localtime(time) );
      next;
    }

    my $delta = 0;
    my $last_time = ${ $disp{$name}->{'time'} };
    $delta = time - $last_time if ( defined $last_time && $last_time > 0 );

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

  eventLog( sprintf( "Deleting %s Tilt", uc($name) ) );

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

    eventLog( sprintf( "Shifting %s Tilt to row $row, col $col", uc($name) ) );

    my $frame = $disp{$name}->{'frame'};
    $frame->gridForget;
    $frame->grid( -row => $row, -column => $col );
  }

  # force the GUI to resize to accommodate the remaining Tilts
  sizeGUI();
}


sub initGUI {
  $mw->protocol( 'WM_DELETE_WINDOW', \&quit );
  $SIG{INT} = \&quit;

  # load the Tilt logo
  $logo = $mw->Photo( -file => './tilt_logo.png' );
  $mw->iconimage( $mw->Photo( -file => './tilt_icon.jpg' ) );

  # create some fonts
  $tinyFont  = $mw->fontCreate( 'tiny',  -family => 'Courier',   -size => 9,  -weight => 'bold' );
  $smallFont = $mw->fontCreate( 'small', -family => 'Helvetica', -size => 12 );
  $largeFont = $mw->fontCreate( 'large', -family => 'Helvetica', -size => 40, -weight => 'bold' );
  $logFont   = $mw->fontCreate( 'log',   -family => 'Courier',   -size => 12 );

  buildMenus();
  searching();
}


sub sizeGUI {
  my $w = shift || $mw;

  # resize the GUI to accommodate the current widgets
  $w->update;
  $w->geometry( $w->reqwidth . 'x' . $w->reqheight );
}


sub loadOpts {
  my $file = 'config.ini';
  return unless ( -e $file );
  open INI, "$file" or die "Could not open '$file' for reading: $!";

  my $name;
  my $name_regex = join "|", @names;
  $name_regex = qr{--($name_regex)}i;

  eventLog('Loading configuration options');

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
      eventLog("Error: invalid Tilt color '$name' for config options");
      next;
    }

    my ($opt, $value) = split /[;,=|]/, $line, 2;
    my $nm = uc($name) . ' Tilt';

    if ( $opt =~ /url/i ) {
      eventLog( "$nm: setting log URL\n$value" );
      $log{$name}{'url'} = $value;

    } elsif ( $opt =~ /beer|name/i ) {
      eventLog( "$nm: setting log beer name\n'$value'" );
      $log{$name}{'beer'} = $value;

    } elsif ( $opt =~ /time|int(erval)|period/i ) {
      eventLog( "$nm: setting log interval = $value min" );
      $log{$name}{'interval'} = $value;

    } elsif ( $opt =~ /sg/i ) {
      eventLog( "$nm: setting cal SG = $value" );
      $cal{$name}{'sg'} = $value;

    } elsif ( $opt =~ /temp/i ) {
      eventLog( "$nm: setting cal temp = $value" );
      $cal{$name}{'temp'} = $value;

    } elsif ( $opt =~ /email/i ) {
      eventLog( "$nm: setting email = $value" );
      $log{$name}{'email'} = $value;

    } else {
      eventLog( "Error: invalid option '$opt' for $nm!" );
    }
  }

  close INI;
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

    foreach my $key (qw/url beer interval email/) {
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
  eventLog( sprintf( "Adding %s Tilt in row 0, col 0", uc( $names[0] ) ) );

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
  sizeGUI();
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

  my $log_menu = $menu->cascade( -label => 'Status', -tearoff => 0 );
  $log_menu->command( -label => 'Show Event Log',   -command => [ \&showLog, 'event'  ] );
  $log_menu->command( -label => 'Show Beacon Data', -command => [ \&showLog, 'beacon' ] );
}


#===============================================
# Logging methods
#===============================================

sub logging {
  my ($menu, $name) = @_;
  resetMenu($menu);

  $menu->command( -label => sprintf( "Setup Log (%s)", defined $log{$name}{'timer'} ? 'ACTIVE' : 'INACTIVE' ), -command => [ \&setupLog, $name ] );
  $menu->command( -label => 'Stop Log', -command => [ \&stopLog,  $name ] );
}


sub setupLog {
  my $name = shift;

  my $log_frame = $mw->Toplevel( -title => 'Log setup' );

  my $r = 0;
  my $width = 30;

  $log_frame->Label( -text => sprintf( "%s Tilt log setup", uc($name) ),
                     -relief => 'groove',
                     -borderwidth => 2,
                     -bg => $colors{$name},
                     -fg => $fg )->
    grid( -row => $r, -column => 0, -sticky => 'we', -columnspan => 2 );

  # log endpoint URL
  $log_frame->Button( -text => 'URL:',
                      -relief => 'flat',
                      -overrelief => 'raised',
                      -command => sub { undef $log{$name}{'url'} } )->grid( -row => ++$r, -column => 0, -sticky => 'e' );
  $log_frame->Entry( -textvariable => \$log{$name}{'url'}, -width => $width )->grid( -row => $r, -column => 1, -sticky => 'w' );

  # force the log interval to be the minimum allowed, if none is yet defined
  $log{$name}{'interval'} = $MIN_LOG_TIME unless ( defined $log{$name}{'interval'} || length( $log{$name}{'interval'} ) );

  # log interval time
  $log_frame->Button( -text => 'Interval (min):',
                      -relief => 'flat',
                      -overrelief => 'raised',
                      -command => sub { undef $log{$name}{'interval'} } )->grid( -row => ++$r, -column => 0, -sticky => 'e' );
  $log_frame->Entry( -textvariable => \$log{$name}{'interval'}, -width => $width )->grid( -row => $r, -column => 1, -sticky => 'w' );

  # beer name
  $log_frame->Button( -text => 'Beer name:',
                      -relief => 'flat',
                      -overrelief => 'raised',
                      -command => sub { undef $log{$name}{'beer'} } )->grid( -row => ++$r, -column => 0, -sticky => 'e' );
  $log_frame->Entry( -textvariable => \$log{$name}{'beer'}, -width => $width )->grid( -row => $r, -column => 1, -sticky => 'w' );

  # email (for Google sheets)
  $log_frame->Button( -text => 'email:',
                      -relief => 'flat',
                      -overrelief => 'raised',
                      -command => sub { undef $log{$name}{'email'} } )->grid( -row => ++$r, -column => 0, -sticky => 'e' );
  $log_frame->Entry( -textvariable => \$log{$name}{'email'}, -width => $width )->grid( -row => $r, -column => 1, -sticky => 'w' );

  $log_frame->Button( -text => 'START LOG', -command => [ \&startLog, $log_frame, $name ] )->grid( -row => ++$r, -column => 0, -sticky => 'w' );
  $log_frame->Button( -text => 'CLOSE', -command => sub { $log_frame->DESTROY } )->grid( -row => $r, -column => 1, -sticky => 'e' );

  $log_frame->Label( -text => 'Status: ',
                     -relief => 'groove',
                     -anchor => 'w',
                     -borderwidth => 2 )->grid( -row => ++$r, -column => 0, -columnspan => 2, -sticky => 'ew' );

  # make the log window appear over the Tilt display which is being affected
  $log_frame->geometry( sprintf( "+%d+%d",
                          $disp{$name}->{'frame'}->rootx + 2,
                          $disp{$name}->{'frame'}->rooty + 2 ) );

  $log_frame->attributes( -topmost => 1 );  # always on top
  sizeGUI($log_frame);  # re-size the log widget
}


sub startLog {
  my ($log_frame, $name) = @_;

  # find the Tk::Label to provide status
  my $status;
  foreach my $w ( $log_frame->gridSlaves ) {
    $status = $w if ( $w->isa('Tk::Label') && $w->cget(-text) =~ /status|error|warn/i );
    last;
  }

  return unless validateLogArgs($status, $name);
  $status->configure( -bg => $bg, -fg => $fg, -text => 'Starting log, standby...' );

  unless ( logPoint($name, 'INIT') ) {
    $status->configure( -bg => 'red', -fg => $fg, -text => 'Error starting log: see event log!' );

  } else {
    $status->configure( -bg => 'green', -fg => $fg, -text => 'Log started' );
    
    my $interval = $log{$name}{'interval'} * 60 * 1000;
    $log{$name}{'timer'} = $mw->repeat( $interval, [ \&logPoint, $name ] );
    logState($name);

    foreach my $w ( $log_frame->gridSlaves ) {
      $w->configure( -state => 'disabled' ) if ( $w->isa('Tk::Entry') );
    }
  }
}


sub validateLogArgs {
  my ($warn, $name) = @_;

  my %check = (
    'url' => \&validateURL,
    'interval' => \&validateInterval,
    'beer' => undef,
    'email' => \&validateEmail
  );

  delete $check{'email'} unless ( defined $log{$name}{'url'} && $log{$name}{'url'} =~ /google/i );

  foreach my $field (keys %check) {
    my $data = $log{$name}{$field};

    # check that data was provided at all
    unless ( defined $data || length($data) ) {
      $warn->configure( -bg => 'red', -fg => $fg, -text => "Error: must provide log $field!" );
      $log{$name}{'interval'} = $MIN_LOG_TIME if ( $field eq 'interval' );
      return;
    }

    next unless ( defined $check{$field} );
    eval { $check{$field}->($data, $name) };

    if ($@) {
      $warn->configure( -bg => 'red', -fg => $fg, -text => "Error: $@!" );
      return;
    }
  }

  return 1;
}


sub validateURL {
  my $url = shift;

  # check that the URL is valid
  my $uri = URI->new($url);

  # check that the URI object was created, has a host, and has http/https scheme
  unless ( defined $uri && $uri->scheme && $uri->host &&
           ($uri->scheme eq 'http' || $uri->scheme eq 'https') ) {
    croak 'Error: invalid log URL!';
  }
}


sub validateInterval {
  my ( $int, $name ) = @_;

  if ( $int !~ /^\d+$/ || $int < $MIN_LOG_TIME || $int > $MAX_LOG_TIME ) {
    $log{$name}{'interval'} = $MIN_LOG_TIME;
    croak "Error: Log interval must be between $MIN_LOG_TIME-$MAX_LOG_TIME minutes!";
  }
}


sub validateEmail {
  my ( $email, $name ) = @_;
  return unless ( $log{$name}{'url'} =~ /google/i );  # email only required for Google sheets

  # mostly I just wanted an excuse to use this ridiculous email regular expression, because hey, it's fun!
  # this is copied from https://emailregex.com, is RFC 5322 compliant, and works 99.99% of the time (apparently)
  my $regex = qr{(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*|"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])};

  croak 'Error: invalid email address!' unless ( $email =~ $regex );
}


sub stopLog {
  my $name = shift;
  return unless ( defined $log{$name}{'timer'} );
  $log{$name}{'timer'}->cancel;
  $log{$name}{'timer'} = undef;
  logState($name);
}


sub logState {
  my $name = shift;
  my $state = defined $log{$name}{'timer'} ? 'ACTIVE' : 'INACTIVE';
  ${ $disp{$name}->{'log_state'} } = "Logging: $state";

  my $status = sprintf( "%s Tilt logging is now $state", uc($name) );

  if ( $state eq 'ACTIVE' ) {
    $status .= sprintf( "\ninterval: %d", $log{$name}{'interval'} );
    $status .= sprintf( "\nURL: %s", $log{$name}{'url'} );
  }

  eventLog($status);
}


sub logPoint {
  my ( $name, $init ) = @_;

  # get current time and convert to Excel time (1990 epoch)
  my $time = time;
  my $log_time = ($time / 86400) + 25569;
  my $last_logged = $log{$name}{'last_logged'} || 0;
  $log{$name}{'last_logged'} = $time;

  # on log initialization, log a point immediately so we can see that things work
  if ($init) {
    push @{ $log{$name}{'data'} }, {
      'time' => $time,
      'sg'   => ${ $disp{$name}->{'sg'}   },
      'temp' => ${ $disp{$name}->{'temp_val'} },
      'rssi' => ${ $disp{$name}->{'rssi'} }
    };
  }

  unless ( defined $log{$name}{'data'} && scalar @{ $log{$name}{'data'} } ) {
    eventLog( sprintf( "%s Tilt: no data found, not logging!", uc($name) ) );
    return;
  }

  # grab this interval's dataset
  my @data = @{ $log{$name}{'data'} };
  my $num_data = scalar @data;

  # if the last data point is prior to the time of the last log point
  # then no "new" data has been collected for this log point
  if ( $data[-1]->{'time'} < $last_logged ) {
    eventLog( sprintf( "%s Tilt: no new data since %s, not logging!", uc($name), strftime( "%D %r", localtime($last_logged) ) ) );
    return;
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

  # first, add this data point to the internal log so we can export it later
  push @{ $log{$name}{'csv'} }, $body;

  # for Google sheets. swap out the RSSI for email address on the first log point
  # this is the indication to Google to create a new log sheet
  if ($init) {
    $body =~ s/(Comment=).*$/$1$log{$name}{'email'}/;
  }

  my @body = split qr/&/, $body;
  my $event = 'Attempting to POST data point';
    $event .= "\nAverage of $num_data points";
    $event .= "\nHTML body:";
    $event .= "\n  " . join "&\n  ", @body;
  eventLog($event);

  # actually POST the data to the cloud
  return sendPoint( $name, $body );
}


sub sendPoint {
  my ( $name, $body ) = @_;

  my $req = HTTP::Request->new( 'POST', $log{$name}{'url'} );
  $req->header( 'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8' );
  $req->content($body);

  my $ua = LWP::UserAgent->new;
  $ua->requests_redirectable( ['GET', 'HEAD', 'POST'] );  # required for Google sheets HTTPS redirects

  my $resp = $ua->request($req);

  # unsuccessful POST
  unless ( $resp->is_success ) {
    eventLog( sprintf( "Error logging data: %s\n%s\n\n%s",
                            $resp->status_line,
                            $resp->message,
                            $resp->decoded_content ) );

  # successful POST
  } else {
    eventLog( sprintf( "Log success: %s", $resp->status_line ) );
    my $data = decode_json( $resp->decoded_content );

    # for Google sheets. need to update the beer name with the name returned by Google
    # this will be the original beer name, appended with a command and unique number
    # e.g. "lager" becomes "lager,123"
    if ( exists $data->{beername} && $log{$name}{'beer'} ne $data->{beername} ) {
      $log{$name}{'beer'} = $data->{beername};
    }

    # for Google sheets. grab the full URL to the log spreadsheet
    if ( exists $data->{doclongurl} && exists $log{$name}{'doclongurl'}
         && $log{$name}{'doclongurl'} ne $data->{doclongurl} ) {
      $log{$name}{'doclongurl'} = $data->{doclongurl};
    }
  }

  return $resp->is_success;
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

  my $log = sprintf( "%s Tilt: water SG calibration complete", uc($name) );
  $log .= sprintf( "\nSG offset: %.3f", $cal{$name}{'sg'} );
  eventLog($log);

}


sub calibrateManual {
  my ($name, $type) = @_;

  my $cal_frame = $mw->Toplevel( -title => uc($type) );

  $cal_frame->Label( -text => sprintf( "%s manual %s calibration", uc($name), uc($type) ),
                     -relief => 'groove',
                     -borderwidth => 2,
                     -bg => $colors{$name},
                     -fg => $fg )->
    grid( -row => 0, -column => 0, -sticky => 'we', -columnspan => 2 );

  my $new_cal = $cal{$name}{$type};

  $cal_frame->Label( -text => sprintf( "%s offset: ", uc($type) ) )->grid( -row => 1, -column => 0, -sticky => 'w' );
  $cal_frame->Entry( -textvariable => \$new_cal )->grid( -row => 1, -column => 1, -sticky => 'e' );

  my $ok_button = $cal_frame->Button( -text => 'OK' )->grid( -row => 2, -column => 0, -sticky => 'w' );
  $cal_frame->Button( -text => 'CANCEL', -command => sub { $cal_frame->DESTROY } )->grid( -row => 2, -column => 1, -sticky => 'e' );

  $ok_button->configure( -command =>
    sub {
      $cal{$name}{$type} = $new_cal;
      $cal_frame->DESTROY;
      my $log = sprintf( "%s Tilt: manual %s calibration complete", uc($name), uc($type) );
      $log .= sprintf( "\n%s offset: %s", uc($type), $new_cal || 'NONE' );
      eventLog($log);
    });

  # make the cal window appear over the Tilt display which is being affected
  $cal_frame->geometry( sprintf( "+%d+%d",
                          $disp{$name}->{'frame'}->rootx + 50,
                          $disp{$name}->{'frame'}->rooty + 50 ) );

  $cal_frame->attributes( -topmost => 1 );  # always on top
  sizeGUI($cal_frame);  # re-size the cal widget
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
# Event/interal log methods
#===============================================

sub showLog {
  my $type = shift || 'event';

  my $window = $type eq 'event' ? \$eventWindow : \$beaconWindow;

  # if already open, just deiconify and raise it
  if (defined $$window) {
    $$window->deiconify;
    $$window->raise;
    return;
  }

  # Create a new top-level window for event messages
  $$window = $mw->Toplevel;
  $window = $$window;  # de-reference
  $window->title( uc($type) . ' LOG' );

  # set a minimum size
  my $minw = $type eq 'event' ? 800 : 550;
  my $minh = 400;
  $window->minsize($minw, $minh);
  $window->geometry( sprintf( "%dx%d+%d+%d", $minw, $minh, $mw->rootx + 50, $mw->rooty + 50 ) );

  my $scrolled = $type eq 'event' ? \$eventScrolled : \$beaconScrolled;
  my $auto = $type eq 'event' ? \$eventAutoScroll : \$beaconAutoScroll;

  # add a button to hide the event window
  my $subFrame = $window->Frame()->pack( -side => 'top', -fill => 'x' );
  my $closeButton = $subFrame->Button(
    -text => 'Close',
  )->pack( -side => 'right', -padx => 3 );

  # checkbox to auto-scroll the event log
  my $autoScroll = $subFrame->Checkbutton(
    -text => 'Auto scroll',
    -variable => $auto,
  )->pack( -side => 'left', -padx => 3 );

  my $clearButton = $subFrame->Button(
    -text => 'CLEAR',
  )->pack( -side => 'left', -padx => 3 );

  # create scrolled text widget
  $$scrolled = $window->Scrolled('Text',
    -width  => 80,
    -height => 20,
    -wrap => 'word',
    -bg => 'black',
    -fg => 'white',
    -scrollbars => 'se',
    -font => $logFont
  )->pack( -side => 'bottom', -fill => 'both', -expand => 1 );

  $scrolled = $$scrolled;  # de-reference
  $scrolled->delete('1.0', 'end');  # clear any existing text

  # insert full history for event log
  if ( $type eq 'event' ) {
    $scrolled->insert( 'end', join( "\n", @eventHistory) );
    $scrolled->insert( 'end', "\n" );  # skip one more line
  }

  $scrolled->see('end');

  # configure the auto-scroll checkbutton to jump to the end, if turning on auto-scroll
  $autoScroll->configure( -command =>
    sub {
      if ( ${ $autoScroll->cget(-variable) } == 1 ) {
        $scrolled->see('end');
      }
    });

  $clearButton->configure( -command => sub { $scrolled->delete('1.0', 'end') } );

  # delete the beacon data when closing window to save resources
  $closeButton->configure( -command =>
    sub {
      $window->withdraw;
      $$auto = 1;
      $clearButton->invoke if ( $type eq 'beacon' );
    });
}


sub beaconLog {
  LOG(shift, 'beacon');
}


sub eventLog {
  LOG(shift, 'event');
}


sub LOG {
  my $message = shift;
  my $type = shift || 'event';

  my $tn = strftime( "%D %r", localtime(time) );

  my @msg = split /\n/, $message;
  my $msg = shift @msg;

  my $line = "[$tn] $msg";
  my $spacer = ' ' x ( length($line) - length($msg) );

  foreach my $m (@msg) {
    $line .= "\n" . $spacer . $m;
  }

  my $scrolled = $type eq 'event' ? $eventScrolled : $beaconScrolled;
  my $auto = $type eq 'event' ? $eventAutoScroll : $beaconAutoScroll;

  # append to the Tk event text widget if it exists
  if (defined $scrolled) {
    unless ( $type eq 'beacon' && !$scrolled->ismapped ) {
      my $newline = $type eq 'event' ? "\n" : "\n\n";
      $scrolled->insert( 'end', "${line}${newline}" );
      $scrolled->see('end') if ($auto);
    }
  }


  # add this line to the event history
  # don't keep history of beacons; too excessive
  push @eventHistory, $line if ($type eq 'event');

  # also print to STDOUT if running in verbose mode
  print "$line\n" if ( $VERBOSE && $type eq 'event' );
  print "$line\n\n" if ( $VERBOSE > 1 && $type eq 'beacon' );
}


#===============================================
# General methods
#===============================================

sub resetMenu {
  my $menu = shift;
  $menu->cget(-menu)->delete( 0, 'end' );
}


sub quit {

  # if we need to signal the thread to exit, might have to
  # implement a termination mechanism (for example, enqueue a special message)?
  # for now, simply detach it
  $bt_thread->detach() if $bt_thread;

  writeOpts();
  exit 0;
}

