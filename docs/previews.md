# Debug previews

Debug builds accept `--preview` to show setup and compatibility screens on a machine with a working Xcode installation. Preview scenarios reuse the application’s views, and refreshes keep showing the selected scenario.

Build the Debug application:

```sh
cmake --preset debug
cmake --build --preset debug
```

Preview a machine without Xcode:

```sh
open -n build/debug/SimStore.app --args --preview no-xcode
```

Preview Xcode without available iOS simulators:

```sh
open -n build/debug/SimStore.app --args --preview no-simulators
```

Preview incompatible builds:

```sh
open -n build/debug/SimStore.app --args --preview incompatible
```

The incompatible scenario substitutes a running iPhone 8 with iOS 12.0 and an empty installed-app list. It loads the real catalog, so cards show the declared system requirements and details show the compatibility warning for builds requiring a newer OS. No iOS 12 runtime is needed. Device actions and app downloads are unsupported in this scenario; they cannot install, launch, or remove an app on a real simulator.

Start a separate instance with real discovery:

```sh
open -n build/debug/SimStore.app
```

The no-simulators and incompatible scenarios use the selected Xcode installation and substitute device inventories. Links and buttons that open the App Store, Xcode, or Device Hub still open the real applications. Each command starts a separate instance, so previews can be viewed side by side. Release builds exclude the preview logic.
