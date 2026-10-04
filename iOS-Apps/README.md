# SISS iPhone apps

Three separate native SwiftUI iPhone applications, using `https://yourallsiss.co.uk`:

| App | Xcode scheme | Bundle identifier |
| --- | --- | --- |
| SISS Staff | SISSStaff | com.siss.staff |
| SISS Admin | SISSAdmin | com.siss.admin |
| Siss-Supervisor | SISSSupervisor | com.siss.supervisor |

Requires iOS 17 or later. Each target has a separate Keychain session. Standard HTTPS verification remains enabled. Passwords are never persisted. The earlier `siss-staff-ios` and `siss-admin-ios` folders are obsolete drafts; this project supersedes them.

**Status: source projects prepared; IPA export and iPhone execution are pending.** This Windows workspace has no Xcode, Mac build connection or Apple signing account. Swift syntax, project structure and API route checks are possible here, but are not a substitute for an Xcode build, simulator tests or physical iPhone checks. Do not treat this as a tested exact clone until the verification checklist below passes.

## Features implemented in source

Staff: cookie login, saved-session device authentication, dashboard, assigned/available shifts, shift details, express interest, authenticated QR image, profile/bank fields, document status, logout. Documents are uploaded through the website, as in the current Android Staff app. Timesheet viewing is included.

Admin: admin/moderator login, dashboard links, staff list and search, create/edit staff, multiple job roles, account status, password reset, deletion confirmation, application and document approval/rejection, document downloads, events, shift creation/editing/allocation/cancellation/deletion, authenticated attendance QR scanner, client/invoice creation and listing, timesheets/CSV export, logout. Shift job requirements and staff job roles use the current server vocabulary; portal access remains staff/moderator/admin.

Supervisor: supervisor-only server authentication; own allocated shifts; shift workspace; team list and record counts; camera/manual QR input; reports restricted to shift times; pre-written activities, incident types, UK entry date/time and notes; finger-drawn signature with clear/undo and confirmation; read-only signed reports. Team scans use the supervisor endpoint and never change attendance. Authentic expired staff attendance codes are accepted by the existing server if the staff member belongs to that supervisor's allocated team. Pending entry retries preserve the UUID/payload; pending signing retries preserve the signature in memory. Admin downloads the signed PDF from the website's Supervisor Records section.

The Android icon vector paths and dark colour palettes are reused. SwiftUI supplies iOS controls and navigation; pixel-exact Android rendering is not verified. Android's settings screen contains several non-persistent controls; the iPhone Account screen currently provides company/domain information and sign out rather than reproducing those misleading controls. Camera, Face ID and API interactions require device verification. No APNs/background push service is configured; the existing email notification service is unchanged.

## Build on a Mac

Open `SISSApps.xcodeproj` in Xcode. Choose a scheme and an iPhone simulator. No CocoaPods, third-party Swift packages or XcodeGen are required. The project generator uses only Python's standard library if regeneration is needed:

```bash
python3 scripts/generate_project.py
bash scripts/build.sh verify
```

`verify` compiles all three targets and runs the Supervisor contract tests on an available iPhone simulator. These tests cover QR token parsing, nullable/decimal wire fields, UK overnight daylight-saving timing, and signature validation. They have not been run on Xcode yet.

For signed IPA export, register all three identifiers in your Apple Developer account, select your team in Xcode, sign in to Xcode with an authorized Apple account and register the receiving iPhones for an ad hoc build. If an identifier is already owned by another team, update it in `scripts/generate_project.py`, regenerate and create matching provisioning profiles.

```bash
APPLE_TEAM_ID=YOUR_TEAM_ID EXPORT_METHOD=release-testing bash scripts/build.sh ipa
```

Output: `build/ipa/SISSStaff/*.ipa`, `build/ipa/SISSAdmin/*.ipa`, `build/ipa/SISSSupervisor/*.ipa`. Use `EXPORT_METHOD=app-store-connect` for an App Store/TestFlight export; uploading and publishing are separate steps. An IPA cannot be installed on arbitrary unregistered iPhones by merely downloading it from a website.

## Build through Codemagic

A Mac cloud builder avoids owning a Mac. Copy this directory's `codemagic.yaml` to the repository root if the repository contains the whole S1ss workspace. Scripts assume the project is under `iOS-Apps/`. If you upload only this directory as a repository, remove `cd iOS-Apps` and the `iOS-Apps/` artifact prefixes.

Run `verify-three-iphone-apps` first; it needs no Apple signing credentials. To run `signed-three-ipa-files`, add one distribution certificate and three ad hoc profiles in Codemagic's Code Signing Identities, using these reference names:

- Certificate: `siss_distribution`
- Profiles: `siss_staff_ad_hoc`, `siss_admin_ad_hoc`, `siss_supervisor_ad_hoc`

The profiles must match the three bundle identifiers, certificate and registered devices. Upload signing inputs through the build provider's secure settings; never commit certificates, private keys or account passwords. The workflow only builds artifacts and does not publish them.

See [Codemagic native iOS builds](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/) and [signing configuration](https://docs.codemagic.io/yaml-code-signing/signing-ios/). Apple documents [Xcode requirements](https://developer.apple.com/xcode/system-requirements/) and [distribution to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

## Before release

1. Run `verify`; fix all Xcode type/build errors and failing tests.
2. Compare each screen against the Android releases on real iPhone sizes, including large accessibility text.
3. Use isolated test users/events to check login/session restore, profile edits, approved/rejected documents, shift allocation, staff QR images, Admin attendance scans and Supervisor records.
4. Check supervisor time boundaries and overnight shifts. Confirm expired QR team scans leave attendance unchanged.
5. Draw and submit a signature, rotate/background the app, exercise failed-request retries, and confirm the website PDF contains the correct report and signature.
6. Export signed IPA files and install each on a registered iPhone. Test denied camera permissions, Face ID, logout, revoked roles and session expiry.

No live users, shifts, reports, database tables or server services were changed while preparing these iPhone projects.
