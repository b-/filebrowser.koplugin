# ![Filebrowser logo](https://avatars.githubusercontent.com/u/35781395?s=48&v=4) Filebrowser KOReader Plugin

*Run Filebrowser server from within KOReader.*

**Warning: only tested on one device, not frequently maintained.** I only have one KOreader device -- a Kindle Pw4, running a relatively recent firmware. (If anyone wants to donate other devices to me, feel free to reach out or file an issue).

This plugin adds a menu item to start and stop the Filebrowser server in the *Network* section of the KOReader menu.

Tested on jailbroken Kindle Paperwhite 4 (2018). It probably works on other devices (including Kobos and other jailbroken Kindles). Please report back (in the Issues tracker!) if it does or doesn't.

## Easy Installation (with bundled `filebrowser` binary)

1. Download and extract [the latest release](https://github.com/b-/filebrowser.koplugin/releases/latest) for your platform, and copy it to the `plugins/filebrowser.koplugin` directory of your KOReader installation.

* If you're unsure about your device's CPU architecture, please refer to [this file](device_query.md) to identify it and select the appropriate bundle.
* If your device is not listed under the Easy Installation section, refer to the Custom Installation section instead.

## Custom Installation (add your own `filebrowser` binary)

1. Copy this repository (at least *_meta.lua* and *main.lua*) into the *plugins/filebrowser.koplugin* directory of your KOReader installation.
2. Download a Filebrowser binary appropriate for your device from [the Filebrowser website](https://github.com/filebrowser/filebrowser/releases/latest) (most likely `linux-armv7-filebrowser.tar.gz`).
3. Extract the archive and copy the `filebrowser` binary to the `plugins/filebrowser.koplugin` directory.

Done! Restart KOReader and you should find the Filebrowser option in the *Network* section under the gear icon in the top menu. After starting Filebrowser, you can use the web GUI to copy files to and from your e-reader. Go to <http://x.x.x.x>, replacing `x.x.x.x` with your e-reader's IP address. The default username and password are `admin` and `admin`, and can be changed from the web interface.

   This will make the Filebrowser GUI available to all devices on the network, so make sure you set a username and strong password in the GUI!

   If you need to reset the password or settings, delete the `plugins/filebrowser.koplugin/filebrowser/filebrowser.db` file.

The Filebrowser binary, configuration files, log files and other data are all stored in `plugins/filebrowser.koplugin/filebrowser/` in the KOReader directory.

## Troubleshooting

- The Filebrowser menu item does not appear after installation.

  First, restart KOReader. If that doesn't help, check if you correctly installed the `filebrowser` binary. The `filebrowser.koplugin` directory should contain `_meta.lua`, `main.lua`, and a folder called `filebrowser` into which you should have copied the latest version of the `filebrowser` binary. Finally, it may be the case that your device does not have the `start-stop-daemon` command available, which we use to run Filebrowser as a background process.

- Filebrowser stops after a moment: the checkbox uncheks itself after reopening the menu.

  This means that Filebrowser is unable to start up. Have a look at the Filebrowser log files at `plugins/filebrowser.koplugin/filebrowser` to find out why Filebrowser is unable to start.

---

This code is primarily based on [syncthing.koplugin](https://github.com/arthurrump/syncthing.koplugin), which is itself primarily based on [SSH.koplugin](https://github.com/koreader/koreader/tree/master/plugins/SSH.koplugin), all of which are available under the [AGPL-3.0 license](https://github.com/koreader/koreader/blob/master/COPYING).
