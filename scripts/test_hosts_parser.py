"""Compile production C on the host; probe ASan/UBSan without installing tools."""
import os
import pathlib
import shlex
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FLAGS = ["-std=c11", "-Wall", "-Wextra", "-Werror", "-Wpedantic",
         "-Wconversion", "-Wshadow", "-Wstrict-prototypes"]
SOURCES = ["Shared/NSHostsParser.c", "Tests/HostsParserTests.c"]
compilers = ([shlex.split(os.environ["CC"])] if os.environ.get("CC") else
             [[name] for name in ("clang", "gcc") if shutil.which(name)])
if not compilers:
    raise SystemExit("No C compiler found; set CC or provide clang/gcc.")

with tempfile.TemporaryDirectory(prefix="netshield-hosts-tests-") as directory:
    directory = pathlib.Path(directory)
    probe = directory / "probe.c"
    probe.write_text("int main(void) { return 0; }\n", encoding="ascii")
    for index, compiler in enumerate(compilers):
        executable = directory / f"hosts-{index}"
        modes = [("strict", ["-O2"])] + [
            (label, ["-O1", "-g", "-fno-omit-frame-pointer",
                     f"-fsanitize={sanitizer}", "-fno-sanitize-recover=all"])
            for label, sanitizer in (("ASan", "address"), ("UBSan", "undefined"))
        ]
        for label, extra in modes:
            if label != "strict":
                probe_executable = directory / f"probe-{index}"
                result = subprocess.run([*compiler, *FLAGS, *extra, str(probe),
                                         "-o", str(probe_executable)],
                                        capture_output=True, text=True)
                if result.returncode == 0:
                    result = subprocess.run([str(probe_executable)],
                                            capture_output=True, text=True)
                if result.returncode:
                    print(f"SKIP {' '.join(compiler)} {label}: probe failed", flush=True)
                    print(result.stderr.strip(), flush=True)
                    continue
            print(f"RUN {' '.join(compiler)} {label}", flush=True)
            subprocess.run([*compiler, *FLAGS, *extra, *SOURCES, "-o", str(executable)],
                           cwd=ROOT, check=True)
            subprocess.run([str(executable)], cwd=ROOT, check=True)
