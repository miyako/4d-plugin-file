#!/usr/bin/env python3
"""Compile actual native sources and the unchanged complete SDK; no plugin build."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
source = args.source.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
sdk = source / "4D Plugin API"
binary = output / "native-ownership"
command = [
    "clang++", "-std=c++11", "-x", "objective-c++", "-g", "-O1",
    "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
    "-Wno-deprecated-declarations", "-Wno-return-type-c-linkage",
    "-include", "Carbon/Carbon.h", "-I", str(sdk), "-I", str(sdk / "Classes"),
    str(Path(__file__).with_name("native_ownership.mm")),
    str(sdk / "4DPluginAPI.c"), str(source / "4DPlugin.cpp"),
    *map(str, sorted((sdk / "Classes").glob("*.cpp"))),
    "-framework", "Cocoa", "-framework", "Carbon", "-o", str(binary),
]
subprocess.run(command, check=True)
environment = dict(os.environ, ASAN_OPTIONS="detect_leaks=0",
                   UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1")
failed = []
tests = ("arrays", "scalars", "callbacks", "path", "path-empty", "path-failure",
         "path-handle-failure", "set-bytes", "copy", "copy-empty",
         "gray", "size", "thumbnail", "picture-params")
for test in tests:
    for empty in ("allocated", "null"):
        result = subprocess.run([str(binary), test, empty], env=environment,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (output / f"{test}-{empty}.log").write_text(result.stdout)
        print(f"{'PASS' if result.returncode == 0 else 'FAIL'} {test} {empty}")
        if result.returncode:
            failed.append(f"{test}/{empty}")
            print(result.stdout[:1600])
print(f"{len(tests) * 2 - len(failed)}/{len(tests) * 2} passed")
sys.exit(bool(failed))
