# Smart Wake icon

The approved smiling sunrise artwork is included as an opaque 1024×1024 PNG in a separate `SmartWakeArtwork.xcassets` catalog for each target. This is an app icon, not an Apple Watch face or complication. The artwork was resized for the app-icon slot without changing its design.

Both targets use the `SmartWakeIcon` app-icon set. The iPhone set uses the iOS single-size slot; the Watch set uses the watchOS single-size slot. Xcode generates the device-specific variants. No custom dark/tinted or layered Icon Composer variants are supplied.

## Add to an existing signed project safely

Do not replace `project.pbxproj` or regenerate the user's existing project just to add icons.

1. Inspect the actual project first and preserve its Team, bundle IDs, entitlements, source fixes and existing assets.
2. Add `iPhoneApp/SmartWakeArtwork.xcassets` to the iPhone group, with target membership **SmartWake only**. Add `WatchApp/SmartWakeArtwork.xcassets` to the Watch group, with membership **SmartWakeWatch only**. Do not add either catalog to both targets; they contain the same icon-set name.
3. In each target's General settings, choose `SmartWakeIcon` as the App Icon source. This sets `ASSETCATALOG_COMPILER_APPICON_NAME` without touching signing.
4. Verify each catalog appears once in that target's Copy Bundle Resources phase. Build and run each scheme, then inspect the installed icon on the phone and Watch. If a different local icon is already configured, reconcile that change instead of overwriting it silently.

Both icon catalogs compiled successfully in the Xcode 26.6 CI simulator builds. Installed-icon rendering on the actual iPhone and Watch still needs visual inspection.

Reference: [Apple: Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).
