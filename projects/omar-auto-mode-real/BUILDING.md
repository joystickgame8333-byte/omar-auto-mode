# Building Omar Auto Mode

## Why It Cannot Be Built In This Windows Workspace

The local workspace currently does not have:

- Theos
- clang for iPhoneOS
- ldid
- iPhoneOS SDK

So building a real `.deb` here would only create another incomplete package.

## Local macOS Build

```sh
export THEOS="$HOME/theos"
git clone --recursive https://github.com/theos/theos.git "$THEOS"
brew install ldid xz make

cd projects/omar-auto-mode-real
make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
```

The package appears in:

```text
projects/omar-auto-mode-real/packages/
```

## GitHub Actions Build

The workflow is here:

```text
.github/workflows/omar-auto-mode-build-rootless.yml
```

Push the workspace to GitHub, run **Build Omar Auto Mode rootless deb**, then
download the generated artifact.

## First Device Test Checklist

Do not test by guessing. Check each step:

1. Install the deb.
2. Confirm the package asks for restart/respring.
3. Open Settings and confirm `Omar Auto Mode` appears as a normal tweak row.
4. Open the tweak page.
5. Confirm buttons are visible:
   - Pick Light Icon Theme
   - Pick Light Home Wallpaper
   - Pick Light Lock Wallpaper
   - Pick Dark Icon Theme
   - Pick Dark Home Wallpaper
   - Pick Dark Lock Wallpaper
   - Apply Now
   - Respring
6. Pick wallpapers from Photos.
7. Pick themes from `/var/mobile/Library/OmarAutoMode/IconThemes`.
8. Tap Apply Now.
9. Check `/var/mobile/Library/OmarAutoMode/ActiveIcons`.

Only after this passes should the icon-rendering hook and wallpaper private API
helper be finalized.

