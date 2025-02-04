#!/usr/bin/perl
###################################################################################
# Author: Ironton Brewing
#  -instagram: @ironton_brewing
#  -email: irontonbrewing@gmail.com
#
# Revision   Date       Comments
# Initial    02/04/25   Initial development
#
# File: data_test.pl
# Purpose: simple utility script to test connectivity between perl/web URL
#          meant to act as utility for verifying the tilt.pl tool
#
# Usage: update your URL, email, and beer name below.
#        run the script in a terminal window and wait for response
#
###################################################################################
use strict;
use warnings;
use LWP::UserAgent;
use JSON;

# enter your URL here. can be 3rd party, or a google sheet
my $url = 'https://script.google.com/macros/<blah>';

# these can be anything you'd like to confirm things are working
my $temp  = 68.4;
my $sg    = 1.024;
my $tilt  = 'green';
my $rssi  = -68;
my $email = 'bob@aol.com';

# if CREATING a new google sheet, your email address needs to be in the comment and NO ",<ID>" in the beer name
# if APPENDING to a google sheet, the beer name needs to have ",<ID>" after the name
# the "<ID>" to use in the beer name will be displayed by this script after sending data to a google sheet
my $new_google_sheet = 0;  # turn this on (1) or off (0)
my $beer = 'Test Lager,3';  # appending data, so use the ",<ID>" format


#=====================================
# Should not need to modify below here
#=====================================

# get current time and convert to Excel time (1990 epoch)
my $time = time;
my $log_time = ($time / 86400) + 25569;

my $comment = $new_google_sheet ? $email : $rssi;

my $body = sprintf( "Timepoint=%f&" .
                    "Temp=%.01f&" .
                    "SG=%.04f&" .
                    "Beer=%s&" .
                    "Color=%s&" .
                    "Comment=$comment", $log_time, $temp, $sg, $beer, uc($tilt) );

# echo the HTML body to see what we're going to send
my @body = split qr{&}, $body;
my $event = 'Attempting to POST data point';
$event .= "\nHTML body:";
$event .= "\n  " . join "&\n  ", @body;
print "$event\n";

my $req = HTTP::Request->new( 'POST', $url );
$req->header( 'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8' );
$req->content($body);

my $ua = LWP::UserAgent->new;
$ua->requests_redirectable( ['GET', 'HEAD', 'POST'] );
my $resp = $ua->request($req);

# failed - print everything to help troubleshoot
unless ( $resp->is_success ) {
  printf( "Error logging data: %s\n\n", $resp->status_line );
  print $resp->message;
  print "\n\n";
  print $resp->decoded_content;
  print "\n\n";

# success - print out the response message
} else {
  printf( "Log success: %s\n\n", $resp->status_line );
  my $data = decode_json( $resp->decoded_content );
  foreach my $key (keys %$data) {
    printf "$key:\n\t%s\n", $data->{$key};
  }
}
