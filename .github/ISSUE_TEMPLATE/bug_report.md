---
name: Bug report
about: Something isn't working as it should
title: "[BUG] "
labels: bug
assignees: ''
---

## Problem description

Clearly explain what is happening.

## Steps to reproduce

1. Run `...` (interactive menu, `--auto`, `--dry-run`)
2. Choose `...`
3. See the error

## Expected behavior

What should have happened instead.

## Screenshots

If applicable, add screenshots that help explain the problem.

## Environment

- Linux Mint version (`cat /etc/linuxmint/info`):
- Cinnamon version (`cinnamon --version`):
- Mint-Doctor version (`./script/mint-doctor.sh --version`):
- Session: X11 / Wayland (`echo $XDG_SESSION_TYPE`):
- Interface language: English / Spanish
- How you ran it: interactive menu / `--auto` / `--dry-run`

## Error messages / terminal output

```
(paste the output here)
```

Each session is logged under `~/.mint-doctor/`. If you can, attach the relevant log, after checking it for anything private.

## Additional context

Which module fails (system information, packages and APT/dpkg, repositories, disk space, boot/GRUB/clock, network, hardware health, Cinnamon, Timeshift), and any other detail that might be useful.
