package com.airsync;

import java.lang.reflect.Method;
import java.util.Locale;

/** Runs under adb shell; changes only scrcpy's virtual physical keyboards. */
public final class KeyboardLayoutBridge {
    public static void main(String[] args) throws Exception {
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        Object binder = serviceManager.getMethod("getService", String.class).invoke(null, "input");
        Class<?> stub = Class.forName("android.hardware.input.IInputManager$Stub");
        Object input = stub.getMethod("asInterface", Class.forName("android.os.IBinder")).invoke(null, binder);
        Class<?> api = Class.forName("android.hardware.input.IInputManager");
        Object[] layouts = (Object[]) api.getMethod("getKeyboardLayouts").invoke(input);
        String requested = args.length > 0 ? args[0] : "";
        String variant = args.length > 1 ? args[1] : "";
        String language = Locale.forLanguageTag(requested).getLanguage();
        Object best = null;
        int bestScore = -1;
        for (Object layout : layouts) {
            Class<?> type = layout.getClass();
            String descriptor = (String) type.getMethod("getDescriptor").invoke(layout);
            Object locales = type.getMethod("getLocales").invoke(layout);
            String tags = (String) locales.getClass().getMethod("toLanguageTags").invoke(locales);
            if ("--list".equals(requested)) {
                System.out.println(descriptor + " " + tags);
                continue;
            }
            int score = -1;
            for (String tag : tags.split(",")) {
                if (Locale.forLanguageTag(tag).getLanguage().equals(language)) {
                    score = Math.max(score, tag.equalsIgnoreCase(requested) ? 100 : 50);
                }
            }
            if (score < 0) continue;
            String name = descriptor.toLowerCase(Locale.ROOT);
            if (name.contains("dvorak") || name.contains("colemak") || name.contains("workman")) score -= 30;
            if ("ru".equals(language)) {
                if ("mac".equals(variant)) score += name.endsWith("russian_mac") ? 30 : 0;
                else score += name.endsWith("russian") ? 30 : 0;
            }
            if ("en".equals(language) && name.endsWith("english_us")) score += 20;
            if (score > bestScore) { bestScore = score; best = layout; }
        }
        if ("--list".equals(requested)) return;
        if (best == null) throw new IllegalArgumentException("No Android keyboard layout for " + requested);
        String descriptor = (String) best.getClass().getMethod("getDescriptor").invoke(best);
        int count = 0;
        int[] ids = (int[]) api.getMethod("getInputDeviceIds").invoke(input);
        Class<?> identifierType = Class.forName("android.hardware.input.InputDeviceIdentifier");
        Method setter;
        try { setter = api.getMethod("setKeyboardLayoutOverrideForInputDevice", identifierType, String.class); }
        catch (NoSuchMethodException oldAndroid) {
            setter = api.getMethod("setCurrentKeyboardLayoutForInputDevice", identifierType, String.class);
        }
        for (int id : ids) {
            Object device = api.getMethod("getInputDevice", int.class).invoke(input, id);
            if (device == null) continue;
            String name = (String) device.getClass().getMethod("getName").invoke(device);
            if (!name.toLowerCase(Locale.ROOT).contains("scrcpy")) continue;
            int keyboardType = (Integer) device.getClass().getMethod("getKeyboardType").invoke(device);
            if (keyboardType != 2) continue; // alphabetic keyboards only
            Object identifier = device.getClass().getMethod("getIdentifier").invoke(device);
            setter.invoke(input, identifier, descriptor);
            System.out.println("SYNCED " + name + " -> " + descriptor);
            count++;
        }
        if (count == 0) { System.out.println("NO_KEYBOARD"); System.exit(3); }
    }
}
