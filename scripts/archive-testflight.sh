#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY_ID="${APP_STORE_CONNECT_KEY_ID:-Y3JLHLYZD5}"
ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-e570c4cf-e394-458c-8cbd-1c2cba6a400f}"
KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
xcodegen generate --spec "$ROOT_DIR/ios/project.yml"
xcodebuild -project "$ROOT_DIR/ios/Herdr.xcodeproj" -scheme Herdr -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ROOT_DIR/build/Herdr.xcarchive" archive \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID"
xcodebuild -exportArchive -archivePath "$ROOT_DIR/build/Herdr.xcarchive" \
  -exportPath "$ROOT_DIR/build/Export" -exportOptionsPlist "$ROOT_DIR/ios/ExportOptions.plist" \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID"
if [[ "${1:-}" == "--upload" ]]; then
  xcrun altool --upload-app -f "$ROOT_DIR/build/Export/Herdr.ipa" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"
fi
