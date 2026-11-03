# Install on your own iPhone and Watch

This is source code, not an installable app or a TestFlight invitation. First compile and test the exact checkout on a Mac. Do not rely on the prototype as your only alarm.

## Check these prerequisites

- A Mac running an OS supported by the selected Xcode release. Xcode 26 requires macOS Sequoia 15.6 or later; newer Xcode versions can have different requirements.
- Xcode 26 or later with iOS and watchOS platform support installed.
- An iPhone on iOS 26 or later and its paired Apple Watch on watchOS 26 or later. Confirm the models support those versions; do not assume an upgrade is available.
- Your existing Apple Account in Xcode, with an available signing team. A free Personal Team can be used for personal-device development. Apple's current watchOS capability table includes HealthKit for free Apple Developer accounts; it does not by itself require a paid membership.
- Free Personal Team provisioning expires after seven days, requiring a rebuild/reinstall. Apple also limits free provisioning to 10 App IDs, three devices and three installed apps per device. This is unsuitable as a permanent unattended alarm installation.

No paid membership purchase is needed to run the Foundation-only tests or simulator compilation. Do not enroll or pay just to troubleshoot this prototype. Signing eligibility and the exact app still need verification in your Xcode account.

## Compile before device installation

1. Open `SmartWake.xcodeproj` and run the commands in the root README: `swift test`, then both unsigned simulator builds.
2. Fix compiler/SDK findings before continuing. The Linux source checkpoint did not execute these steps.
3. In Signing & Capabilities, set the same existing team for both `SmartWake` and `SmartWakeWatch`, leaving automatic signing selected.
4. Set a unique phone bundle ID, such as `com.yourname.smartwake`. Set the Watch bundle ID to that phone ID plus `.watchkitapp`. Set the Watch build setting `COMPANION_APP_BUNDLE_IDENTIFIER` to the phone bundle ID.
5. Keep the existing Watch HealthKit entitlement. If Xcode needs it configured in Signing & Capabilities, add HealthKit to `SmartWakeWatch`. No clinical records, background delivery or HealthKit writes are used.

Do not regenerate the project after local signing customization unless those changes are also preserved in the generator.

## Device steps you perform

1. Connect the iPhone to the Mac and unlock it. Approve Trust only for your own Mac. Keep the paired Watch nearby, unlocked and sufficiently charged.
2. If Xcode requests Developer Mode, review Apple's warning. Developer Mode reduces some device security, requires a restart and confirmation on the device. Enable it yourself on the iPhone and Watch only if you choose to proceed. The option may appear only after Xcode starts pairing.
3. Choose the `SmartWake` scheme and your physical iPhone as destination, then Run. Xcode signs and installs the phone app with its embedded Watch companion.
4. Choose `SmartWakeWatch` and the paired physical Watch as destination, then Run. Resolve any actual pairing/signing errors rather than assuming successful installation from a completed phone build.
5. On the phone, explicitly allow alarms and test a manual wake-up a few minutes ahead. On the Watch, explicitly allow sleep read access and optional motion recording, then send the summary to the paired phone.
6. Complete `DEVICE_TEST_PLAN.md`, including locked-phone delivery, system Stop, puzzle completion, emergency stop, relaunch and interrupted scheduling. Keep a separate trusted alarm throughout.

Your Apple password, signing keys, provisioning profiles and device identifiers do not belong in this repository. Do not send passwords or secret signing material in chat. No device installation, account setup or security-setting change is performed by the repository itself.

## Official Apple references

- [Account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account/)
- [watchOS capabilities by membership](https://developer.apple.com/help/account/reference/supported-capabilities-watchos/)
- [Configuring HealthKit](https://developer.apple.com/documentation/xcode/configuring-healthkit-access)
- [Running on devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Developer Mode and its security warning](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Xcode 26 requirements](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
