#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# A stable signer lets WebKit's Keychain access survive executable changes.
# Ad-hoc signing uses the binary hash as its identity and prompts after rebuilds.
identity=${TONK_TOWN_SIGN_IDENTITY:-}
if [[ -z "$identity" ]]; then
    identities=$(security find-identity -v -p codesigning)
    development_ids=()
    while IFS= read -r fingerprint; do
        [[ -n "$fingerprint" ]] && development_ids+=("$fingerprint")
    done < <(printf '%s\n' "$identities" | sed -nE 's/.* ([[:xdigit:]]{40}) "Apple Development:.*$/\1/p')
    if [[ ${#development_ids[@]} -ne 1 ]]; then
        echo "Set TONK_TOWN_SIGN_IDENTITY to a code-signing identity from security find-identity -v -p codesigning." >&2
        echo "For an explicit ad-hoc build, use TONK_TOWN_SIGN_IDENTITY=-; Keychain prompts may recur after rebuilding." >&2
        exit 1
    fi
    identity=${development_ids[0]}
fi
swift build
app="$PWD/.build/Tonk.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp .build/debug/TonkTown "$app/Contents/MacOS/TonkTown"
cp Resources/Info.plist "$app/Contents/Info.plist"
for bundle in .build/debug/textual_Textual.bundle .build/debug/swiftui-math_SwiftUIMath.bundle; do
    ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
codesign --force --sign "$identity" --timestamp=none "$app"
codesign --verify --strict "$app"
echo "$app"
