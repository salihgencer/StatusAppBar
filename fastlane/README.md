fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac register

```sh
[bundle exec] fastlane mac register
```

App ID + App Store Connect uygulama kaydı (ilk kurulumda bir kez)

### mac build

```sh
[bundle exec] fastlane mac build
```

App Store arşivi + PKG üret

### mac beta

```sh
[bundle exec] fastlane mac beta
```

PKG üret + TestFlight'a yükle

### mac release

```sh
[bundle exec] fastlane mac release
```

PKG üret + App Store'a yükle (incelemeye GÖNDERMEZ)

### mac metadata

```sh
[bundle exec] fastlane mac metadata
```

Yalnızca metadata + screenshots yükle (fastlane/metadata/tr, screenshots/tr)

### mac submit

```sh
[bundle exec] fastlane mac submit
```

App Store'daki mevcut sürümü incelemeye gönder

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
