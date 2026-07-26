#!/usr/bin/env python3
"""
GudaBags offline test runner.

Two passes:
  1. Syntax-checks every .lua file in the addon (pure-Python Lua parser).
  2. Runs the locale matrix harness against a real Lua interpreter, loading the
     addon's actual rule code with the WoW API stubbed out.

Requires:  pip install luaparser lupa

Usage:     python tests/run.py            # from the addon root
           python tests/run.py --syntax   # syntax pass only
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def iter_lua_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in (".git", "tests")]
        for name in sorted(filenames):
            if name.endswith(".lua"):
                yield os.path.join(dirpath, name)


def syntax_pass():
    try:
        from luaparser import ast
    except ImportError:
        print("SKIP syntax pass: pip install luaparser")
        return 0

    failed = 0
    checked = 0
    for path in iter_lua_files():
        with io.open(path, encoding="utf-8-sig") as fh:
            src = fh.read()
        checked += 1
        try:
            ast.parse(src)
        except Exception as exc:  # noqa: BLE001 - report any parse failure
            failed += 1
            print("FAIL %s" % os.path.relpath(path, ROOT))
            for line in str(exc).splitlines()[:5]:
                print("      " + line)
    print("syntax: %d file(s) checked, %d failed" % (checked, failed))
    return failed


def harness_pass():
    try:
        import lupa
    except ImportError:
        print("SKIP harness pass: pip install lupa")
        return 0

    script = os.path.join(ROOT, "tests", "locale_matrix.lua")
    os.environ["GUDABAGS_PATH"] = ROOT.replace("\\", "/")
    runtime = lupa.LuaRuntime(unpack_returned_tuples=True)
    with io.open(script, encoding="utf-8") as fh:
        src = fh.read()
    try:
        runtime.execute(src)
    except lupa.LuaError as exc:
        print("LUA ERROR:\n%s" % exc)
        return 1
    return 0


def main():
    syntax_only = "--syntax" in sys.argv
    failures = syntax_pass()
    if not syntax_only:
        print("")
        # Lua writes straight to the C stdout, so flush Python's buffer first
        # or the two passes interleave out of order.
        sys.stdout.flush()
        failures += harness_pass()
        sys.stdout.flush()
    print("")
    if failures:
        print("FAILED (%d)" % failures)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
