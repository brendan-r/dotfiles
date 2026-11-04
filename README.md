# Dotfiles

Very much a work in progress - you don't want to use them.

## New machine

First, install the prerequisites if needed:

- **macOS:** run `xcode-select --install` and wait for Command Line Tools to finish
  installing. Full Xcode is not needed; Bash and curl are already available.
- **Debian:** run `sudo apt update && sudo apt install git curl ca-certificates`.

Then paste this into your terminal as your normal user, without `sudo`:

```sh
( script=$(curl -qfsSL https://raw.githubusercontent.com/brendan-r/dotfiles/master/dotfiles) && /bin/bash -c "$script" -- bootstrap )
```

## Run again

```sh
# Open the installer from its default checkout location.
~/projects/dotfiles/dotfiles install
```

