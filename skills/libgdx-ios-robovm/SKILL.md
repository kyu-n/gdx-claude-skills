---
name: libgdx-ios-robovm
description: Use when writing libGDX Java/Kotlin code targeting iOS via RoboVM — IOSApplication launcher, IOSApplicationConfiguration, robovm.xml, robovm.properties, RoboVM reflection limitations (forceLinkClasses), iOS lifecycle, file access on iOS, safe area insets for notch/Dynamic Island, screen density, haptics, or on-screen keyboard. Use when debugging classes missing at runtime on iOS, black screen on launch, or UI hidden behind the notch.
---

# libGDX iOS / RoboVM Backend

Reference for the iOS backend using RoboVM. Covers launcher setup, RoboVM compilation model, lifecycle, file access, and platform quirks.

## Launcher

```java
import org.robovm.apple.foundation.NSAutoreleasePool;
import org.robovm.apple.uikit.UIApplication;

import com.badlogic.gdx.backends.iosrobovm.IOSApplication;
import com.badlogic.gdx.backends.iosrobovm.IOSApplicationConfiguration;

public class IOSLauncher extends IOSApplication.Delegate {
    @Override
    protected IOSApplication createApplication() {
        IOSApplicationConfiguration config = new IOSApplicationConfiguration();
        config.orientationLandscape = true;
        config.orientationPortrait = false;
        config.useAccelerometer = false;   // disable if unused — saves battery
        config.useCompass = false;
        config.preferredFramesPerSecond = 60;  // 0 = max (default)
        config.useHaptics = true;          // REQUIRED for Gdx.input.vibrate() on iOS
        return new IOSApplication(new MyGame(), config);
    }

    public static void main(String[] argv) {
        NSAutoreleasePool pool = new NSAutoreleasePool();
        UIApplication.main(argv, null, IOSLauncher.class);
        pool.close();
    }
}
```

### IOSApplicationConfiguration

| Option | Type | Default | Notes |
|---|---|---|---|
| `orientationLandscape` | boolean | true | Enable landscape orientations |
| `orientationPortrait` | boolean | true | Enable portrait orientations |
| `useAccelerometer` | boolean | true | Disable to save battery if unused |
| `useCompass` | boolean | true | Disable to save battery if unused |
| `preferredFramesPerSecond` | int | 0 | Target FPS. 0 = max supported by screen (typically 60). Set 30 for battery savings. |
| `useHaptics` | boolean | false | **Must be true** for `Gdx.input.vibrate()` to work |

## Backend Variants: Classic vs MetalANGLE

libGDX provides two iOS backend options (both use RoboVM):

**Note:** Multi-OS Engine (MOE) and `gdx-backend-moe` are defunct — do NOT recommend them. The only supported iOS backends are RoboVM-based.

| | Classic (`ios-robovm`) | MetalANGLE (`ios-robovm-metalangle`) |
|---|---|---|
| **Graphics** | OpenGL ES directly | OpenGL ES → Metal translation |
| **Status** | Works, but OpenGL ES deprecated by Apple (iOS 12, 2018) | **Recommended for new projects** (libGDX 1.12+) |
| **Gradle dependency** | `gdx-backend-robovm` | `gdx-backend-robovm-metalangle` |
| **robovm.xml framework** | `OpenGLES` | `Metal` (no `OpenGLES`) |
| **Game code changes** | — | **None** — same libGDX API |

MetalANGLE translates OpenGL ES calls to Metal transparently. Your game code stays identical — only the backend dependency and robovm.xml frameworks differ. The launcher class (`IOSApplication.Delegate`) does not change.

**For new projects, use `gdx-backend-robovm-metalangle`.** Apple could remove OpenGL ES in a future iOS version. MetalANGLE provides forward-compatibility with no code changes.

**Migrating from classic to MetalANGLE:** Change the Gradle dependency and swap `OpenGLES` → `Metal` in robovm.xml frameworks. No game code changes required.

**Apple Silicon Macs:** The classic `ios-robovm` backend does not support arm64 iOS simulators. On Apple Silicon Macs the default simulator is arm64, so the classic backend fails. Either use an x86_64 simulator (Rosetta) or switch to the MetalANGLE backend, which supports arm64 simulators. This is another reason MetalANGLE is recommended for new projects.

## RoboVM: How It Works

RoboVM compiles Java bytecode **ahead-of-time (AOT) to native ARM**. There is no JVM on the device. This means:
- All code must be known at compile time
- **No dynamic class loading** — `Class.forName()` with runtime-determined strings fails
- **Unreferenced classes are stripped** — classes only used via reflection are removed
- Standard Java collections, math, strings, threading all work fine
- JVM-specific features like `Runtime.exec()`, `ProcessBuilder` do not work (iOS sandbox)

### robovm.xml

Main RoboVM configuration file. Key sections:

```xml
<config>
    <!-- Frameworks: choose ONE set based on your backend -->

    <!-- MetalANGLE backend (recommended): -->
    <frameworks>
        <framework>UIKit</framework>
        <framework>Metal</framework>
        <framework>QuartzCore</framework>
        <framework>CoreGraphics</framework>
        <framework>OpenAL</framework>
        <framework>AudioToolbox</framework>
        <framework>AVFoundation</framework>
    </frameworks>

    <!-- Classic backend: replace Metal with OpenGLES above -->
    <!-- <framework>OpenGLES</framework> instead of <framework>Metal</framework> -->

    <!-- Assets bundled with the app -->
    <resources>
        <resource>
            <directory>../assets</directory>
        </resource>
    </resources>

    <!-- CRITICAL: Force-link classes used via reflection -->
    <forceLinkClasses>
        <pattern>com.mygame.entities.**</pattern>
        <pattern>com.mygame.data.SaveData</pattern>
    </forceLinkClasses>

    <!-- Info.plist entries -->
    <iosInfoPList>
        <dict>
            <key>CFBundleDisplayName</key>
            <string>My Game</string>
            <key>UIStatusBarHidden</key>
            <true/>
        </dict>
    </iosInfoPList>
</config>
```

### robovm.properties

Simple key-value file for app metadata:

```properties
app.id=com.mygame.ios
app.name=MyGame
app.version=1.0
app.build=1
app.mainclass=com.mygame.ios.IOSLauncher
```

### Reflection / forceLinkClasses (CRITICAL)

RoboVM strips classes it can't statically determine are used. If your game uses libGDX `Json`, `ReflectionPool`, or any reflection-based instantiation, those classes **will be missing at runtime on iOS** while working fine on desktop and Android.

**Fix:** Add `<forceLinkClasses>` patterns in `robovm.xml`:

```xml
<forceLinkClasses>
    <pattern>com.mygame.entities.**</pattern>   <!-- ** = all classes including subpackages -->
    <pattern>com.mygame.items.*</pattern>        <!-- * = classes in this package only -->
</forceLinkClasses>
```

**Symptom:** `ClassNotFoundException` or `ReflectionException` on iOS only. Game works on desktop/Android.

### Build Commands (Gradle)

```bash
./gradlew ios:launchIPhoneSimulator    # run on iPhone simulator
./gradlew ios:launchIOSDevice          # run on connected physical device
./gradlew ios:createIPA                # build IPA for distribution
```

First build is slow (AOT compilation). Subsequent builds use caching.

## Lifecycle

| Event | Behavior |
|---|---|
| App goes to background | `pause()` called |
| App returns to foreground | `resume()` called |
| **OpenGL context on pause** | **Preserved** — textures NOT destroyed (unlike Android) |
| App terminated | `dispose()` called, but iOS rarely terminates cleanly — usually just suspends |

**Key difference from Android:** On iOS, the OpenGL context is **preserved** when the app backgrounds. You do NOT need to reload textures on resume. Android destroys the GL context on pause, requiring texture reloads — this does not happen on iOS.

**`dispose()` is unreliable on iOS.** iOS typically suspends apps rather than terminating them. Save critical state in `pause()`, not `dispose()`.

## File Access

| Method | iOS Location | Writable |
|---|---|---|
| `Gdx.files.internal()` | App bundle (resources/) | No (read-only) |
| `Gdx.files.local()` | App's Documents directory | Yes |
| `Gdx.files.external()` | App's Documents directory | Yes |

**`local()` and `external()` map to the same directory on iOS.** There is no separate external storage concept — iOS apps are sandboxed. Unlike Android, there is no SD card, no shared storage, and no file permissions to request.

## Platform Quirks

### Safe Area / Notch (iPhone X+)

**Use `Gdx.graphics.getSafeInsetTop()` etc.** to get safe area insets for notch/Dynamic Island/home indicator:

```java
float topInset    = Gdx.graphics.getSafeInsetTop();     // notch / Dynamic Island
float bottomInset = Gdx.graphics.getSafeInsetBottom();  // home indicator bar
float leftInset   = Gdx.graphics.getSafeInsetLeft();    // landscape notch
float rightInset  = Gdx.graphics.getSafeInsetRight();

// Offset your UI: don't place buttons in the inset area
float safeTop = Gdx.graphics.getHeight() - topInset;
```

These return **pixel** values. Account for them when positioning UI elements near screen edges. Critical on all iPhone X and newer (notch and Dynamic Island).

### Screen Density

```java
float density = Gdx.graphics.getDensity();
// iPhone Retina: 2.0
// iPhone Plus / Pro Max: 3.0
```

`Gdx.graphics.getWidth()`/`getHeight()` return **pixels** (not iOS points). The density gives the Retina scale factor.

### No Back Button

iOS has no system back button. `Input.Keys.BACK` is Android-only. You must provide in-app navigation (on-screen back buttons, swipe gestures). Do not use `Gdx.input.setCatchKey(Input.Keys.BACK, true)` on iOS — it has no effect.

### On-Screen Keyboard

```java
// Show/hide the soft keyboard directly
Gdx.input.setOnscreenKeyboardVisible(true);   // show
Gdx.input.setOnscreenKeyboardVisible(false);  // hide

// Or show a native text input dialog
Gdx.input.getTextInput(listener, "Title", "default text", "hint");
```

**Gotcha:** The soft keyboard covers the bottom portion of the screen. Your UI must account for this — move text fields up or resize the viewport. The native dialog (`getTextInput`) is modal and blocks game input.

### Haptics

`Gdx.input.vibrate()` works on iOS **only if `useHaptics = true`** in `IOSApplicationConfiguration`. Without it, vibrate calls are silently ignored.

```java
Gdx.input.vibrate(50);   // duration in ms (iOS may round to standard haptic pattern)
```

## Common Mistakes

1. **Assuming OpenGL context is lost on iOS background** — That's Android. On iOS the GL context is preserved. No texture reloading needed on resume.
2. **Not using `<forceLinkClasses>` for reflection** — Classes only referenced via reflection (Json, ReflectionPool) are stripped by RoboVM AOT compilation. Add patterns in robovm.xml. Symptom: `ClassNotFoundException` on iOS only.
3. **Thinking `Gdx.files.external()` differs from `Gdx.files.local()` on iOS** — They both map to the Documents directory. No separate external storage on iOS.
4. **Using `Gdx.input.setCatchKey(Input.Keys.BACK, true)` on iOS** — iOS has no back button. This is Android-only. Provide in-app navigation instead.
5. **Not accounting for safe area insets** — On iPhone X+ the notch/Dynamic Island and home indicator overlap the screen. Use `Gdx.graphics.getSafeInsetTop()` etc. to offset UI.
6. **Expecting `dispose()` to be called** — iOS typically suspends apps, not terminates them. Save state in `pause()`.
7. **Using wrong Gradle task names** — The correct tasks are `ios:launchIPhoneSimulator`, `ios:launchIOSDevice`, `ios:createIPA`. Not `ios:launchIOSSimulator` or `ios:launchIPhoneDevice`.
8. **Forgetting `useHaptics = true` in config** — `Gdx.input.vibrate()` silently does nothing on iOS without this config option.
9. **Using JVM-specific features** — `Runtime.exec()`, `ProcessBuilder`, dynamic class loading with runtime-determined names all fail on iOS. RoboVM compiles to native ARM — there is no JVM.
10. **Not knowing about `Gdx.graphics.getSafeInsetTop()`** — This is a libGDX API. Do not write custom RoboVM/UIKit code to get safe area insets — libGDX provides it cross-platform.
11. **Using the classic `ios-robovm` backend for new projects without considering MetalANGLE** — Apple deprecated OpenGL ES in iOS 12. The MetalANGLE backend (`gdx-backend-robovm-metalangle`) is recommended for forward-compatibility. Same libGDX API, different backend dependency only.
12. **Including `OpenGLES` framework in robovm.xml when using the MetalANGLE backend** — MetalANGLE uses `Metal` framework instead. Using the wrong framework set causes black screen or crash on launch.
13. **Running the classic `ios-robovm` backend on an arm64 iOS simulator (Apple Silicon Mac)** — The classic backend doesn't support arm64 simulators. Use an x86_64 simulator (Rosetta) or switch to the MetalANGLE backend.
