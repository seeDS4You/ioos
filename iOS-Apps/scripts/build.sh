#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
command -v xcodebuild >/dev/null || { echo "This build requires macOS with Xcode." >&2; exit 1; }
mode="${1:-verify}"
schemes=(SISSStaff SISSAdmin SISSSupervisor)
if [[ "$mode" == "verify" ]]; then
  for scheme in "${schemes[@]}"; do
    xcodebuild -project SISSApps.xcodeproj -scheme "$scheme" -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "build/$scheme" CODE_SIGNING_ALLOWED=NO build
  done
  destination="${SIMULATOR_DESTINATION:-}"
  if [[ -z "$destination" ]]; then
    destination="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; data=json.load(sys.stdin); phones=[x["udid"] for key,items in data["devices"].items() if "iOS" in key for x in items if x.get("isAvailable") and "iPhone" in x["name"]]; print("platform=iOS Simulator,id="+phones[0] if phones else "")')"
  fi
  [[ -n "$destination" ]] || { echo "Install an iOS simulator runtime in Xcode." >&2; exit 1; }
  xcodebuild -project SISSApps.xcodeproj -scheme SISSSupervisor -configuration Debug -destination "$destination" -derivedDataPath build/Tests CODE_SIGNING_ALLOWED=NO -resultBundlePath "build/ContractTests-$(date +%s).xcresult" test
elif [[ "$mode" == "ipa" ]]; then
  : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer team ID}"
  method="${EXPORT_METHOD:-release-testing}"
  case "$method" in release-testing|app-store-connect|debugging) ;; *) echo "Use release-testing, app-store-connect, or debugging." >&2; exit 1 ;; esac
  mkdir -p build/ipa
  export APPLE_TEAM_ID EXPORT_METHOD="$method"
  python3 - <<'PY'
import os,plistlib
with open('build/ExportOptions.plist','wb') as f:
    plistlib.dump({'method':os.environ['EXPORT_METHOD'],'teamID':os.environ['APPLE_TEAM_ID'],'signingStyle':'automatic','destination':'export','manageAppVersionAndBuildNumber':False},f)
PY
  for scheme in "${schemes[@]}"; do
    xcodebuild -project SISSApps.xcodeproj -scheme "$scheme" -configuration Release -destination 'generic/platform=iOS' -archivePath "build/$scheme.xcarchive" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" -allowProvisioningUpdates archive
    xcodebuild -exportArchive -archivePath "build/$scheme.xcarchive" -exportPath "build/ipa/$scheme" -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
  done
else
  echo "Usage: bash scripts/build.sh [verify|ipa]" >&2; exit 1
fi
