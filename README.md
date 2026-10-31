# Wireless Peripheral Battery

An Omarchy bar widget that shows the battery level of your wireless mouse,
keyboard, headset and game controller, without Solaar or HeadsetControl.

<p align="center">
  <img src="preview.png" alt="Bar showing mouse 68%, keyboard 82% and headset 41%" width="420">
</p>

- **Hover** for the full device names, charging state, and when a sleeping
  device was last read.
- A device at **20 %** or below switches to the theme's alert color.
- ⚡ means the device is charging.
- Devices that are asleep or switched off are **dimmed** and keep their last
  reading for up to 12 hours instead of disappearing from the bar.

## Why another battery plugin?

Most battery widgets for Omarchy read from **UPower**. That works for many
Bluetooth devices, but UPower only knows what the kernel reports, and several
common wireless devices are missing there. On the development machine, UPower
listed the G502 mouse but neither the G915 TKL keyboard (on its own Lightspeed
receiver) nor the Arctis 7 headset.

The usual fix is to install Solaar and HeadsetControl, which give your user
account raw access to the devices (see [why that matters](#why-a-root-service)).

This plugin reads the devices directly and covers those gaps. It needs no extra
package, and all your session receives is the percentages. If UPower already
shows all your devices, a UPower-based widget is simpler and needs no setup.

## How it works

```
 /dev/hidraw*  ─┐
 /sys (kernel)  ─┴►  peripheral-battery.service  ──►  /run/peripheral-battery/status.json  ──►  bar widget
  (root only)       (root, sandboxed, every 30 s)         (world-readable, percentages only)    (reads the file)
```

The plugin comes in two parts:

1. **A system service** (`service/`). A short Python script, standard library
   only, that a systemd timer runs every 30 seconds ([configurable](#refresh-interval)).
   It asks each device for its battery level, adds the device batteries the
   kernel already tracks (read from sysfs, without talking to the device),
   writes the result to
   `/run/peripheral-battery/status.json`, and exits. Nothing stays resident: a
   run uses about 60 ms of CPU and 8 MB of memory, and lasts under a second,
   mostly spent waiting for the radio replies.
2. **The bar widget** (`BarWidget.qml`). It reads that JSON file and nothing
   else. It starts no process and needs no permission.

### Why a root service?

Reading the battery means talking to the devices through `/dev/hidraw*`,
which only root can open. Solaar and HeadsetControl solve this with udev
rules that give **your user account** raw read/write access to the devices
(and, for Solaar, to `/dev/uinput`). That access is broader than battery
reading. Any program running as you could also see the raw reports going
through a Logitech receiver, including keystrokes, or inject input.

This plugin keeps that access with root, inside a heavily sandboxed service
that has no capabilities, no network, a read-only filesystem and only hidraw
devices. All your desktop session gets is a few percentages in a JSON file.

[docs/security.md](docs/security.md) has the full details: every message sent
to the devices, the sandbox settings, and what is and is not protected.

## Supported hardware

| Device | Connection | Status |
|---|---|---|
| Logitech G502 Lightspeed | Lightspeed receiver `046d:c539` | Tested |
| Logitech G915 TKL | Lightspeed receiver `046d:c545` | Tested |
| SteelSeries Arctis 7 (2019) | USB dongle `1038:12ad` | Tested |
| Other Logitech HID++ 2.0 devices with battery feature `0x1000`, `0x1001` or `0x1004` (Unifying, Bolt, Lightspeed, cable or Bluetooth) | | Should work, untested |
| SteelSeries Arctis 7 (2017), 1 Wireless, 7P, 7X, 9, 7+, 7P+, 7X+, Nova 3P/3X Wireless, Nova 5/5X, Nova 7/7X/7P (all revisions), Nova Pro Wireless | USB dongle or base station | Should work, untested (requests from HeadsetControl) |
| Device batteries reported by the kernel: PlayStation, Xbox (xpadneo), Switch and Steam controllers, Wiimotes, Apple Magic devices, HID devices reporting a battery, Logitech HID++ 1.0 through `hid-logitech-hidpp` | Any | Should work, untested |
| Bluetooth headphones and other devices whose battery only BlueZ knows | | Not supported, use a UPower widget |

Devices the kernel reports are matched by name with the ones read directly,
so a Logitech device appears once, with the more detailed direct reading.

If your device works, or does not, please open an issue with its name and
the output of `cat /run/peripheral-battery/status.json`.

## Install

Plugins run as unsandboxed code inside `omarchy-shell`, and this one also
installs a root service. Read the code before installing: the service script
and the install script are short.

**1. Add the plugin**

```bash
omarchy plugin add https://github.com/gexavi/omarchy-peripheral-battery --enable
```

**2. Install the service**

`omarchy plugin add` never runs sudo or install scripts, so this step is
yours to run:

```bash
sudo ~/.config/omarchy/plugins/gexavi.peripheral-battery/service/install.sh
```

The script:

- copies the reader to `/usr/local/lib/peripheral-battery/`, root-owned. The
  root service never runs code from your home directory, which your user
  could modify.
- installs `peripheral-battery.service` and `peripheral-battery.timer` into
  `/etc/systemd/system/`,
- enables the timer and does a first reading.

Python 3 is required, and Omarchy ships with it.

**3. Restart the shell**

```bash
omarchy restart shell
```

Until the service is installed, the widget shows 󰂑. Hover over it for the
install command.

## Refresh interval

The service reads the devices every **30 seconds** by default. That costs
about 3 minutes of CPU time per day in total, which is negligible. Each read
also sends one radio message to each device. Compared to normal use (a moving
mouse sends hundreds per second) that is very little, but if you want to
spare your devices' batteries as much as possible, read less often.

To change the interval, add a systemd drop-in. Do not edit the installed unit:
`install.sh` overwrites it, while it keeps drop-ins.

```bash
sudo mkdir -p /etc/systemd/system/peripheral-battery.timer.d
printf '[Timer]\nOnUnitActiveSec=\nOnUnitActiveSec=2min\n' \
  | sudo tee /etc/systemd/system/peripheral-battery.timer.d/interval.conf
sudo systemctl daemon-reload
sudo systemctl restart peripheral-battery.timer
```

Replace `2min` with the interval you want (`45s`, `1min`, `5min`…). Keep
the empty `OnUnitActiveSec=` line. Without it, systemd adds your interval to
the default one instead of replacing it.

Keep it at **5 minutes or less**. The widget dims the readings and warns in
its tooltip when the data is more than 10 minutes old, because that usually
means the service stopped.

To go back to the default:

```bash
sudo rm -r /etc/systemd/system/peripheral-battery.timer.d
sudo systemctl daemon-reload
sudo systemctl restart peripheral-battery.timer
```

## Update

```bash
omarchy plugin update gexavi.peripheral-battery
sudo ~/.config/omarchy/plugins/gexavi.peripheral-battery/service/install.sh
omarchy restart shell
```

`omarchy plugin update` only updates the files in your home directory. The
root service keeps running the copy in `/usr/local/lib` until you re-run
`install.sh`, so you can review the diff first. If the service and the widget
versions differ, the tooltip warns you.

The shell restart is needed because Quickshell keeps the previous widget code
in memory.

## Uninstall

```bash
sudo ~/.config/omarchy/plugins/gexavi.peripheral-battery/service/uninstall.sh
omarchy plugin remove gexavi.peripheral-battery
```

## Coming from Solaar or HeadsetControl

The plugin works whether or not they are installed. If you installed them
only to read battery levels, you can remove them:

```bash
sudo pacman -Rs solaar headsetcontrol
```

This also removes their udev rules (`42-logitech-unify-permissions.rules`,
`70-headsets.rules`), and with them your user's raw access to the devices.
Keep them if you use them for something else, such as DPI, lighting or
sidetone.

## Troubleshooting

```bash
systemctl status peripheral-battery.timer       # is the timer active?
systemctl list-timers peripheral-battery.timer  # last and next run
journalctl -u peripheral-battery.service        # errors only: routine runs are not logged
sudo systemctl start peripheral-battery.service # read the devices now
cat /run/peripheral-battery/status.json         # what the widget sees
```

| Widget shows | Meaning |
|---|---|
| 󰂑, dimmed | `status.json` missing: the service is not installed or has not run yet |
| Readings dimmed | Not updated for 10 minutes: the timer is stopped |
| A device is missing | It was never seen awake, or it is not supported |
| A kernel-reported device shows 󰂄 | Its kind (mouse, controller…) could not be told from its name or driver |

## Credits

The HID++ 2.0 battery features and the Li-ion voltage-to-percent curve
come from [Solaar](https://github.com/pwr-Solaar/Solaar). The Arctis 7 status
status requests come from [HeadsetControl](https://github.com/Sapd/HeadsetControl).
This plugin reimplements the few requests it needs and contains no code from
either project.

## License

MIT
