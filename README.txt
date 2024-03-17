INTRO:
    thanks for checking out my project!
    this is a Tilt Hydrometer application written in perl/Tk, which will read bluetooth signals,
    parse raw Tilt data, and log the information to a third party URL, such as Brewfather.
    This is similar to the Tilt Pi software offered by Tilt.

CONTACT:
    irontonbrewing@gmail.com

BACKGROUND:
    My intent behind this, other than just for fun, was to avoid the need to flash my Raspberry Pi
    SD card to run the Tilt Pi web server, and to make custom tweaks and features.
    As a systems/software engineer by trade, I work with perl/Tk on a daily basis in my day job.
    Yes, it's "old", but perl 5 is still maintained and updated, and I prefer the syntax over Python.

LEGAL:
    I have full permisson from Tilt (Noah Nibarron) to "sandbox" with their data format. This program
    is in no way intended to circumvent, override, or plagiarize any of Tilt's own software. This program
    offers no warranty, guarantee, or support mechanism. This program as designed, simply reads data over
    a BLE (bluetooth low energy) digital singal and posts formatted information to a web URL. The intended
    use of this software is to read Tilt digital hydrometer data for use in tracking beer fermentation
    progress, for use in beer brewing, or other liquid density applications only.

SYSTEM REQUIREMENTS:
    this program is only written and tested with Unix/Linux operating systems in mind.
    support with Microsoft Windows may be possible with third party perl installations,
    such as Strawberry perl, but no testing or guarantees can be given.

    a bluetooth radio antenna is required to take BLE readings
    built-in or external antennas will work.

    several third party software installations are required, as outlined in the
    installation instructions below.

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

# install LWP::UserAgent module to make HTTP requests
# note this will also install a LOT of dependencies (but good ones!)
sudo cpanm LWP::UserAgent

# if you want to run hcitool and hcidump as a normal user, grant the appropriate capabilites to the executables
# note this may have security implications
sudo setcap 'cap_net_raw,cap_net_admin+eip' `which hcitool`
sudo setcap 'cap_net_raw,cap_net_admin+eip' `which hciconfig`
