# Keyboard layout helper

AirSync uses this small dex helper over the existing authorized ADB connection to match scrcpy and embedded-mirror UHID keyboards to the active Mac input language. It changes only alphabetic devices named scrcpy. It does not replace the Android IME or use the clipboard.

The Swift coordinator watches Mac input-source changes and retries while a new UHID keyboard starts. Android must provide the matching physical-keyboard layout. Android 16's layout override API and older Android's current-layout API are selected by reflection; unsupported APIs report an error rather than changing the phone IME.

To regenerate the checked-in resource, install a JDK, download the official R8 compiler, then run:

```sh
R8_JAR=/absolute/path/to/r8.jar sh tools/android-keyboard/build.sh
```

Set `TASK_JAVA_BIN` if the JDK is not at `/opt/homebrew/opt/openjdk/bin`.

On-device validation was performed with Android 16 and scrcpy 5.0, switching Mac ABC to Russian and back. Earlier Android APIs are a compatibility fallback and have not been device-tested.
