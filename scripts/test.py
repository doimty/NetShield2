"""Compile and run the production shared-code regression tests on macOS."""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(ROOT / "scripts/test_hosts_parser.py")], check=True)
for script, arguments in [
    ("check_localization.py", []),
    ("check_localization.py", ["--self-test"]),
    ("check_localization_bundle.py", ["--self-test"]),
]:
    subprocess.run([sys.executable, str(ROOT / "scripts" / script), *arguments], check=True)
if sys.platform != "darwin":
    raise SystemExit("Native regression tests require macOS and the Xcode command-line tools.")

sources = [
    "Tests/RegressionTests.m",
    "Tests/RecoveryTests.m",
    "Tests/HostsImportTests.m",
    "Tests/HostsDownloadTests.m",
    "App/NSHostsDownload.m",
    "Shared/NSHostsImport.m",
    "Shared/NSHostsParser.c",
    "App/NSFilterRemoval.m",
    "App/NSFilterRestart.m",
    "Shared/NSPolicy.m",
    "Shared/NSPermissionQueue.m",
    "Shared/NSPolicyCache.m",
    "Shared/NSStoreLock.m",
    "Shared/NSStore.m",
    "FilterControl/NSPermissionNotifications.m",
    "FilterControl/NSDomainResolver.m",
]
with tempfile.TemporaryDirectory(prefix="netshield-tests-") as directory:
    executable = pathlib.Path(directory) / "regression-tests"
    # Apple SDKs expose DNSService APIs through the automatically linked
    # libSystem; there is no separate libdns_sd to request here.
    subprocess.run([
        "xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-fblocks",
        "-DNS_TESTING=1", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter",
        "-framework", "Foundation", "-framework", "UserNotifications",
        *sources, "-o", str(executable),
    ], cwd=ROOT, check=True)
    subprocess.run([str(executable)], cwd=ROOT, check=True)
