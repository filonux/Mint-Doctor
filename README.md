<img src="assets/icon.png" alt="Mint-Doctor" width="140" height="140">

# Mint-Doctor

Terminal autorepair tool for Linux Mint 22.3 "Zena" with Cinnamon: it detects, explains and fixes —with your permission— the most common problems in this specific version of the system.

![Bash 4+](https://img.shields.io/badge/bash-%3E%3D4.0-4EAA25?logo=gnubash&logoColor=white) ![Linux Mint 22.3 Cinnamon](https://img.shields.io/badge/Linux%20Mint-22.3%20Cinnamon-87CF3E?logo=linuxmint&logoColor=white) [![GPLv3 license](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE.txt)

---

> 🇬🇧 This is the main documentation. For the Spanish version, see [🇪🇸 Leer en español](README.es.md).

## Contents

- [What is Mint-Doctor?](#what-is-mint-doctor)
- [The main advantage](#the-main-advantage)
- [Installation](#installation)
- [Commands](#commands)
- [Usage](#usage)
- [Compatibility](#compatibility)
- [Turn it into an app with Scriptya](#turn-it-into-an-app-with-scriptya)
- [Language](#language)
- [Tests](#tests)
- [Contributing](#contributing)
- [License](#license)

## What is Mint-Doctor?

Mint-Doctor is a terminal script that checks Linux Mint 22.3 with Cinnamon for the specific problems that actually affect this version: GPG keys that fail after an update, an NVIDIA driver that stopped loading with the new kernel, a package that breaks GTK4 application rendering, accumulated kernels eating disk space, a Timeshift setup that looks configured but never actually created a snapshot...

It is not a generic cleaner that promises to leave the PC "as good as new". It is closer to a mechanic's checklist, built from Mint's own release notes and from issues that keep coming back in its official forum: it checks one point, explains what it found and why it matters, and only acts when you confirm it.

<img width="559" height="575" alt="menu-en-mintdoctor" src="https://github.com/user-attachments/assets/58fe66fb-83f6-4337-96f1-906086498926" />

<img width="842" height="593" alt="mint-doctor-menu" src="https://github.com/user-attachments/assets/afad29bd-0504-458c-beb2-9c902d8dd4f2" />

## The main advantage

Any "maintenance" script can empty a trash bin or run `apt autoremove`. What makes Mint-Doctor different is that it knows about *documented* Mint 22.3 issues specifically, including:

- `nvidia-driver-470` stops working with the HWE 6.14+ kernel series that Mint 22.2/22.3 installs by default on new systems.
- `gstreamer1.0-vaapi` can break rendering in WebKit/GTK4-based applications.
- PipeWire can cut audio over HDMI outputs, an issue already documented in the release notes.
- The shutdown timeout was reduced to 10s starting with Mint 22.2, and this can force services that take longer to close to be terminated.
- Cinnamon "spices" (applets, desklets, extensions) installed manually can stop loading after the move from Cinnamon 6.4 to 6.6.
- With Secure Boot enabled, a newly built DKMS module (proprietary NVIDIA, VirtualBox...) can remain unloaded because its MOK signature is missing, without making the cause obvious at first glance.

On top of that, the design is deliberately conservative:

- **Nothing is applied without asking.** In automatic mode (`--auto`), normal repairs are assumed to be "yes", but **importing a new GPG key always requires your explicit confirmation**, even in that mode: without a terminal to ask, the key is skipped instead of being accepted automatically.
- **Simulation mode** (`--dry-run`) shows exactly what it would do without changing anything.
- **It does not run as root.** It only asks for the `sudo` password when a specific action needs it, and explains why.
- **Backups before editing software source files**, plus a detailed session log.
- **It does not automate things that should stay manual.** Repairing an NTFS volume marked as "dirty", enrolling a Secure Boot MOK key or changing an official Mint repository that does not match your version are cases where it explains what is happening and how you can fix it yourself.

## Installation

```bash
git clone https://github.com/filonux/Mint-Doctor.git
cd mint-doctor
chmod +x script/mint-doctor.sh
./script/mint-doctor.sh
```

There is nothing else you need to install beforehand: everything it uses by default is already present on Linux Mint. If a module detects that a specific tool is missing (`smartmontools`, `TLP`, `Timeshift`, `psmisc`...), it offers to install it, with your confirmation.

## Commands

| Command | What it does |
| --- | --- |
| `./script/mint-doctor.sh` | Opens the interactive menu |
| `./script/mint-doctor.sh --dry-run` | Simulates actions; nothing is applied |
| `./script/mint-doctor.sh --auto` | Checks and repairs everything automatically, without the menu |
| `./script/mint-doctor.sh --dry-run --auto` | Full simulated scan, without the menu |
| `./script/mint-doctor.sh -h`, `--help` | Shows the help |
| `./script/mint-doctor.sh -v`, `--version` | Shows the version |
| `./script/mint-doctor.sh --lang es` | Forces the interface to Spanish |
| `./script/mint-doctor.sh --lang en` | Forces the interface to English |

## Usage

When started without arguments, Mint-Doctor opens a menu with a quick status panel (disk, RAM, APT, pending updates, network) and ten options:

1. **System information** — distribution, kernel, Cinnamon, CPU, disk/RAM and session type. Read-only; it changes nothing.
2. **Packages and APT/dpkg** — stale locks, half-installed packages, broken dependencies, held packages, `pkexec`/`sudo` permissions.
3. **Software repositories** — repositories using an older Mint/Ubuntu codename, missing or invalid GPG keys, unreachable repositories and inherited keyrings.
4. **Disk space and cache** — APT cache, accumulated old kernels, thumbnail cache, trash, systemd journal size, unused Flatpak runtimes, missing Flathub remote and an almost-full `/boot` partition.
5. **Boot, GRUB and clock** — GRUB entry for the current kernel, pending reboot, RTC clock problems when dual-booting Windows, NTFS volumes marked as "dirty", NTP synchronization, failed systemd services and forced shutdowns caused by the new timeout.
6. **Network connectivity** — software-blocked radios (`rfkill`), Internet connectivity and DNS resolution checked separately.
7. **Hardware health** — disk S.M.A.R.T. status, battery health and TLP power management, DKMS modules not rebuilt after a new kernel, NVIDIA 470 driver compatibility, sound server, Secure Boot and modules rejected because of missing signatures, VirtualBox Guest Additions.
8. **Cinnamon desktop** — recent crashes, desktop shortcuts not marked as trusted, the `gstreamer1.0-vaapi` package, multimedia codecs, a session running without 3D acceleration and third-party Cinnamon spices compatibility with the installed Cinnamon version.
9. **Backups (Timeshift)** — whether a configured destination exists, whether there are real snapshots (not only a completed setup wizard), their age and whether automatic scheduling is enabled.
10. **Run all modules** — the same sequence used by `--auto`, but asking before each step.

Each session is logged under `~/.mint-doctor/` (permissions restricted to your user; the 20 most recent are kept). At the end, a summary shows how many problems were detected, how many were fixed and how many were skipped.

To run it unattended (for example from a `systemd --user` timer or `cron`), use `--auto`: it does not open any menu and returns exit code `1` when a problem remains unresolved (`0` otherwise), so a launcher can tell whether anything still needs attention. If a graphical session is available and `notify-send` is installed, it also sends a desktop notification.

## Compatibility

Made and tested for **Linux Mint 22.3 "Zena" with Cinnamon** (6.6.x). On startup it checks the installed version; if it detects anything outside the 22.x series, it warns you but **does not block execution**: modules that depend on Cinnamon or Mint-specific paths will simply have nothing to check on a different system.

- Requires Bash, `sudo` and the standard tools found on a Mint Cinnamon installation (APT/dpkg, systemd...).
- Must be run as a normal user, never as root and never with `sudo script/mint-doctor.sh`.
- Some modules are naturally optional: battery/TLP only applies to laptops, DKMS/Secure Boot only when third-party drivers are involved, and Flatpak only when it is installed.

## Turn it into an app with Scriptya

[**Scriptya**](https://github.com/filonux/Scriptya), another tool by the same author, turns any script into a standalone app with its own icon, integrated into the Cinnamon menu and/or desktop —and also lets you launch, update or uninstall it from a single menu, without having to write a `.desktop` file by hand.

`mint-doctor.sh` already includes the metadata Scriptya knows how to read (`MENU`, `DESCRIPTION`, `TERMINAL`), so you only need to point it at the project folder to get it integrated.

## Language

Mint-Doctor includes the full interface in English and Spanish. This main README is in English; the Spanish documentation is available in [README.es.md](README.es.md).

By default, the script follows the effective locale (`LC_ALL`, then `LC_MESSAGES`, then `LANG`). If it is Spanish, the interface is Spanish; otherwise it uses English. On GNU/Linux, `LANGUAGE` is also respected when it explicitly prefers English or Spanish, except under the `C`/`POSIX` locale.

You can also choose the language explicitly without editing the script:

```bash
./script/mint-doctor.sh --lang es
./script/mint-doctor.sh --lang en

MINT_DOCTOR_LANG=es ./script/mint-doctor.sh
MINT_DOCTOR_LANG=en ./script/mint-doctor.sh
```

When both are used, `--lang` takes precedence over the environment variable. If an unsupported language is requested, Mint-Doctor falls back to English.

## Tests

The project includes a regression suite for syntax, locale detection, both interface languages, dynamic translations, command-line parsing, the yes/no prompts and a full `--dry-run --auto` pass. The English and Spanish dry-runs also compare the commands they plan to execute, so changing the language cannot silently change a repair.

Run it from the project root:

```bash
./tests/test.sh
```

The suite uses Bash, Python 3 and the standard Linux tools already available in a typical Mint installation. It never applies a real repair: the end-to-end pass always runs in `--dry-run`.

## Contributing

Issues and pull requests are welcome; there are templates in `.github/` for reporting bugs or proposing improvements. The full guide is in [CONTRIBUTING.md](.github/CONTRIBUTING.md), and the code of conduct is in [CODE_OF_CONDUCT.md](.github/CODE_OF_CONDUCT.md). To report a security issue, see [SECURITY.md](.github/SECURITY.md) instead of opening a public issue.

## License

GPLv3. See [LICENSE.txt](LICENSE.txt).

---

Made by **[Filonux](https://github.com/filonux)**.
