# ![Tilt Logo](tilt_logo.png) Intro

Thanks for checking out my project!  
This is a Tilt Hydrometer application written in perl/Tk, which will read bluetooth signals, parse raw Tilt data, and log the information to Tilt's [Google sheet app](https://tilthydrometer.com/pages/app) or a third party URL, such as [Brewfather](https://docs.brewfather.app/integrations/tilt-hydrometer). This is similar to the Tilt Pi software offered by Tilt.

# Installation (Recommended)

Download and install the Debian package from the [irontonbrewing](https://github.com/irontonbrewing/projects) PPA GitHub.  
This automates dependency installations, and allows for easy updates later.

1) Copy and execute the below commands to allow the ``irontonbrewing`` project distribution as a trusted package source.
```bash
curl -s --compressed "https://irontonbrewing.github.io/projects/dist/KEY.gpg" | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/irontonbrewing.gpg >/dev/null
sudo curl -s --compressed -o /etc/apt/sources.list.d/irontonbrewing.list "https://irontonbrewing.github.io/projects/dist/irontonbrewing.list"
```
2) Install tilt-perl
```bash
sudo apt update
sudo apt install tilt-perl
```

# Installation (Manual)

Download and install the Debian package from the [irontonbrewing](https://github.com/irontonbrewing/projects) PPA GitHub, **without** adding ``irontonbrewing`` as a trusted package source. 
1) [Download](https://github.com/irontonbrewing/projects/tree/main/dist) the latest ``tilt-perl-<version>.deb``
2) Move the ``.deb`` package to ``/tmp``
   ```bash
   mv tilt-perl-1.1.deb /tmp
   ```
3) Install the package
   ```bash
   sudo apt install /tmp/tilt-perl-1.1.deb
   ```

# Installation (git clone)

1) Clone git repository from GitHub
    ```bash
    git clone https://github.com/irontonbrewing/tilt_perl $HOME/tilt-perl
    ```

2) Install dependencies
    ```bash
    sudo apt-get install bluez-hcidump perl perl-tk libjson-perl libwww-perl liblwp-protocol-https-perl libssl-dev zlib1g-dev
    ```

    - hcidump for reading raw bluetooth advertised packet data
    - Perl-Tk for Perl GUI toolkit
    - perl JSON for Google Sheets and user config setting
    - LWP::UserAgent module to make HTTP requests
    - HTTPS support for LWP::UserAgent (requires the OpenSSL dev and zlib dev packages)

# Usage

1) In a terminal window, simply execute the program.
   - a 'verbose' switch will echo events.
   - a 'very verbose' switch will echo events and beacon data.
   ```bash
   tilt
   tilt -v
   tilt -v -v
   ```
> [!NOTE]
> The tilt application is installed in ``/usr/bin``

2) A generic "searching" screen is displayed until a Tilt is detected
    - if nothing appears within 30 seconds or so, make sure your Tilt is on, floating, and in range.
    - also make sure there is no obvious source of bluetooth interference, and that your device's bluetooth is functioning in general.

3) The Tilt status will appear in place of the search window once a Tilt device is found.
   - data is updated automatically in real time.

4) To start logging: ``Configure => Logging => <color>``
    - In the new popup window, enter the URL end-point, a logging interval (in minutes, minimum 15), and a beer name
    - A valid email is also required, for Google sheets logging only
    - Click START
    - Any errors will be displayed in the "Status:" area
> [!NOTE]
> logging gathers data over the specified interval and posts an average of the collection

5) To add a calibration offset: ``Configure => Calibrate => <color> => <cal choice>``
    - Manual calibrations will open a popup window to enter the offset
> [!NOTE]
> - only a single calibration offset is currently supported; device level calibration in prepared sugar solutions is recommended.
> - calibration will be applied upon the next subsequent reading

# Known issues

Testing on Raspberry Pi/Debian Bookworm often produces a warning at launch. This is a benign issue with the `hcitool` command and can be ignored.
```bash
Set scan parameters failed: Input/output error
```
    
# Other

1) Exporting data: ``File => Export data => <color>``
    - When logging is active, the tool stores the logged data locally to be exported on the local file system.
    - The user will be prompted with a browser dialogue to select a location and file name.
    - The data will be exported in CSV format.
> [!NOTE]
> the "comments" field is currently used to record average signal strength (RSSI)

2) User settings:
    - Any logging or calibration settings will be automatically saved to a config.json file in ``$HOME/.tilt``, then automatically loaded on the next program start.
    - The settings saved are color-specific and can support multiple devices.

3) Status logs: status about the tool can be viewed from one of two logs.

   - ``Status => Show Event Log``
     - Displays timestamped information about actions the tool has taken, such as adding/removing Tilts, adjusting calibration settings, and logging information.
     - This information is stored and is not lost when closing this log, unless the "CLEAR" button is pressed.
     - This information is echoed to the terminal window when using the "-v" command line switch.

    - ``Status => Show Beacon Data``
        - Displays timestamped information from the individual Tilt bluetooth packets as they are processed by the tool. This is meant for troubleshooting and is not normally of interest, but could be used to confirm bluetooth functionality.
        - This is information is excessive, is not stored, and is lost when closing this log.
        - This information is echoed to the terminal window when using the "-v -v" command line switch.
> [!TIP]
> this log can be monitored to obtain the device's battery age, which is periodically reported.
     
# About

## Contact

irontonbrewing@gmail.com

[@ironton_brewing](https://www.instagram.com/ironton_brewing)

## Background

My intent behind this, other than just for fun, was to avoid the need to flash my Raspberry Pi SD card to run the Tilt Pi web server, and to make custom tweaks and features.
As a systems/software engineer by trade, I work with perl/Tk on a daily basis in my day job. Yes, it's "old", but perl 5 is still maintained and updated, and I prefer the syntax over Python.

## Legal

I have full permission from Tilt to "sandbox" with their data format and to use their logo. This program is in no way intended to circumvent, override, or plagiarize any of Tilt's own software.
This program offers no warranty, guarantee, or support mechanism. This program as designed, reads data over a BLE (bluetooth low energy) digital signal and posts formatted information to a web URL.
The intended use of this software is to read Tilt digital hydrometer data for tracking beer fermentation progress, for use in brewing beer, or other liquid density applications only.
Please see ``LICENSE.txt`` for full licensing.

## System Requirements

- a bluetooth radio antenna is required to take BLE readings - built-in or external antennas will work.
- several third party software installations are required, as outlined in the installation instructions.
- this program is only written and tested with Unix/Linux operating systems in mind. Specifically, Raspberry Pi Debian based systems, though any Linux distribution would likely work.
Support for Microsoft Windows may be possible with third party perl installations, such as Strawberry perl, but no testing or guarantees can be given.

## Reference

- Tilt hydrometer: https://tilthydrometer.com/
- Tilt iBeacon data format: https://kvurd.com/blog/tilt-hydrometer-ibeacon-data-format/
- Tilt iBeacon git python libraries: https://github.com/frawau/aioblescan  (not used here)
