INTRO:
    thanks for checking out my project!
    this is a Tilt Hydrometer application written in perl/Tk, which will read bluetooth signals,
    parse raw Tilt data, and log the information to Tilt's Google sheet app or a third party URL, such as Brewfather.
    This is similar to the Tilt Pi software offered by Tilt.

CONTACT:
    irontonbrewing@gmail.com

BACKGROUND:
    My intent behind this, other than just for fun, was to avoid the need to flash my Raspberry Pi
    SD card to run the Tilt Pi web server, and to make custom tweaks and features.
    As a systems/software engineer by trade, I work with perl/Tk on a daily basis in my day job.
    Yes, it's "old", but perl 5 is still maintained and updated, and I prefer the syntax over Python.

LEGAL:
    I have full permission from Tilt (Noah Nibarron) to "sandbox" with their data format and to use their logo.
    This program is in no way intended to circumvent, override, or plagiarize any of Tilt's own software.
    This program offers no warranty, guarantee, or support mechanism. This program as designed, reads data over
    a BLE (bluetooth low energy) digital signal and posts formatted information to a web URL. The intended
    use of this software is to read Tilt digital hydrometer data for tracking beer fermentation progress,
    for use in brewing beer, or other liquid density applications only. Please see LICENSE.txt for full licensing.

SYSTEM REQUIREMENTS:
    This program is only written and tested with Unix/Linux operating systems in mind.
    Specifically, Raspberry Pi Debian based systems, though any Linux distribution would likely work.
    Support for Microsoft Windows may be possible with third party perl installations,
    such as Strawberry perl, but no testing or guarantees can be given.

    A bluetooth radio antenna is required to take BLE readings - built-in or external antennas will work.

    Several third party software installations are required, as outlined in the installation instructions below.

REFERENCE:
    Tilt hydrometer: https://tilthydrometer.com/
    Tilt iBeacon data format: https://kvurd.com/blog/tilt-hydrometer-ibeacon-data-format/
    Tilt iBeacon git python libraries: https://github.com/frawau/aioblescan  (not used here)


TO INSTALL:

# install hcidump for reading raw bluetooth advertised packet data
sudo apt-get install hcidump

# install Perl-Tk for Perl GUI toolkit
sudo apt-get install perl-tk

# install cpanm in order to easily install CPAN Perl modules (CPAN itself should be installed by default)
sudo cpan App::cpanminus

# Google Sheets and user config settings use JSON (good to have anyway)
sudo cpanm JSON

# install LWP::UserAgent module to make HTTP requests
# note this will also install a LOT of dependencies (but good ones!)
sudo cpanm LWP::UserAgent

# for Google Sheets, must have HTTPS support for LWP::UserAgent
# this requires the OpenSSL dev and zlib dev packages
sudo apt-get install libssl-dev
sudo apt-get install zlib1g-dev
sudo cpanm LWP::Protocol::https

# if you want to run hcitool and hcidump as a normal user, grant the appropriate capabilities to the executables
# then remove the 'sudo' calls in the perl script
# note this may have security implications
sudo setcap 'cap_net_raw,cap_net_admin+eip' `which hcitool`
sudo setcap 'cap_net_raw,cap_net_admin+eip' `which hciconfig`


TO USE:

1) In a terminal window, simply execute the program.
    >> ./tilt.pl  

    -a 'verbose' switch will echo events.
    >> ./tilt.pl -v

    -a 'very verbose' switch will echo events and beacon data.
    >> ../tilt.pl -v -v

2) A generic "searching" screen is displayed until a Tilt is detected
    -if nothing appears within 30 seconds or so, make sure your Tilt is on, floating, and in range.
    -also make sure there is no obvious source of bluetooth interference, and that your device's
     bluetooth is functioning in general

3) The Tilt status will appear in place of the search window once a Tilt device is found.
   -data is updated automatically in real time.

4) To start logging:
    a) Configure => Logging => <color>
    b) In the new popup window, enter the URL end-point, a logging interval (in minutes, minimum 15), and a beer name
    c) A valid email is also required, for Google sheets logging only
    d) Click START
    e) Any errors will be displayed in the "Status:" area
    f) Note: logging gathers data over the specified interval and posts an average of the collection

5) To add a calibration offset:
    a) Configure => Calibrate => <color> => <cal choice>
    b) Manual calibrations will open a popup window to enter the offset
    c) Note: only a single calibration offset is currently supported.
             device level calibration in prepared sugar solutions is recommended
    d) Note: calibration will be applied upon the next subsequent reading

Exporting data:
    File => Export data => <color>
    When logging is active, the tool stores the logged data locally to be exported on the local file system.
    The user will be prompted with a browser dialogue to select a location and file name.
    The data will be exported in CSV format.
    Note that the "comments" field is currently used to record average signal strength (RSSI)

User settings:
    Any logging or calibration settings will be automatically saved to a config.json
    file in the local directory, then automatically loaded on the next program start.
    The settings saved are color-specific and can support multiple devices.

Status logs:
    Status about the tool can be viewed from one of two logs.

    1) Status => Show Event Log
        Displays timestamped information about actions the tool has taken, such as
        adding/removing Tilts, adjusting calibration settings, and logging information.
        This information is stored and is not lost when closing this log, unless the "CLEAR" button is pressed.
        This information is echoed to the terminal window when using the "-v" command line switch.

    2) Status => Show Beacon Data
        Displays timestamped information from the individual Tilt bluetooth packets
        as they are processed by the tool. This is meant for troubleshooting and is not
        normally of interest, but could be used to confirm bluetooth functionality.
        This is information is excessive, is not stored, and is lost when closing this log.
        This information is echoed to the terminal window when using the "-v -v" command line switch.
        Note: this log can be monitored to obtain the device's battery age, which is periodically reported.