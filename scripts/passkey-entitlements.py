"""Extract the desktop passkey entitlements from an approved Apple profile."""
import datetime
import plistlib
import sys
from pathlib import Path

profile = plistlib.loads(Path(sys.argv[1]).read_bytes())
entitlements = profile["Entitlements"]
if entitlements.get("com.apple.application-identifier") != "8WVKS2F24C.xyz.tonk":
    raise SystemExit("Passkey builds require the Tonk Labs xyz.tonk profile.")
if profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit("The passkey provisioning profile has expired.")
domains = entitlements.get("com.apple.developer.associated-domains", [])
if "*" not in domains and "webcredentials:tonk.network" not in domains:
    raise SystemExit("The provisioning profile does not allow the Tonk domain.")
selected = {key: entitlements[key] for key in (
    "com.apple.application-identifier", "com.apple.developer.team-identifier"
)}
selected["com.apple.developer.associated-domains"] = ["webcredentials:tonk.network"]
Path(sys.argv[2]).write_bytes(plistlib.dumps(selected))
