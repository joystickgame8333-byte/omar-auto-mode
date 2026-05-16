# Omar Auto Mode

Independent rootless jailbreak tweak for automatic light/dark assets.

This is the real Theos project, not the earlier plist-only test package.

## What This Project Builds

- `OmarAutoMode.dylib`
  - Loads in SpringBoard.
  - Watches light/dark appearance.
  - Applies the selected mode when it changes.
  - Receives apply notifications from Settings.

- `OmarAutoModePrefs.bundle`
  - Real PreferenceBundle with controllers.
  - Uses picker screens and buttons, not raw path text fields.
  - Lets the user pick light/dark icon themes and wallpapers.

## Build

This requires Theos, an iPhoneOS SDK, clang, and ldid.

```sh
make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
```

The current Windows workspace cannot compile this. Use macOS/Xcode/Theos or the
included GitHub Actions workflow.

## Rootless Install Paths

Theos rootless packaging installs layout files under `/var/jb`.

```text
/var/jb/Library/PreferenceLoader/Preferences/OmarAutoMode.plist
/var/jb/Library/PreferenceBundles/OmarAutoModePrefs.bundle
/var/jb/Library/MobileSubstrate/DynamicLibraries/OmarAutoMode.dylib

/var/mobile/Library/OmarAutoMode/
  ActiveIcons/
  IconThemes/
  Wallpapers/
```

## Current Truth

This source is the first serious build shape. The preference UI is real. The
SpringBoard runtime currently prepares active icon folders and emits hooks for
future wallpaper/icon rendering. A complete independent icon engine still needs
SpringBoard icon image hooks after this project can be compiled and tested on
iOS 16.4.

