# Setup screen previews

Debug builds accept `--preview` to show setup screens on a machine with a working Xcode installation. Preview scenarios reuse the application’s views and actions, and refreshes keep showing the selected scenario.

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

Start a separate instance with real discovery:

```sh
open -n build/debug/SimStore.app
```

The second scenario uses the selected Xcode installation and substitutes an empty device inventory. Buttons that open the App Store, Xcode, or Device Hub still open the real applications. Each command starts a separate instance, so previews can be viewed side by side. Release builds exclude the preview logic.
