"""Compile every shipped Lua file and inspect the real LuaJIT function limits.

No game chunks are executed, so this check never loads or changes game saves.
The runtime's jit.util reflection includes nested function prototypes.
"""
from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def library_path(explicit: str | None) -> str:
    candidates = [explicit, os.environ.get("LUAJIT_LIBRARY")]
    if os.name == "nt":
        candidates += [str(ROOT / "runtime/lua51.dll"),
                       str(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "LOVE/lua51.dll")]
    candidates += [ctypes.util.find_library("luajit-5.1")]
    for candidate in candidates:
        if candidate and (Path(candidate).is_file() or os.name != "nt"):
            return candidate
    raise RuntimeError("LuaJIT was not found; pass --library or set LUAJIT_LIBRARY.")


class Compiler:
    def __init__(self, path: str):
        self.lib = ctypes.CDLL(path)
        signatures = {
            "luaL_newstate": ([], ctypes.c_void_p),
            "luaL_openlibs": ([ctypes.c_void_p], None),
            "luaL_loadbuffer": ([ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p], ctypes.c_int),
            "lua_pcall": ([ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int], ctypes.c_int),
            "lua_tolstring": ([ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)], ctypes.c_void_p),
            "lua_close": ([ctypes.c_void_p], None),
        }
        for name, (args, result) in signatures.items():
            function = getattr(self.lib, name)
            function.argtypes, function.restype = args, result

    def inspect(self, path: Path) -> dict:
        state = self.lib.luaL_newstate()
        if not state:
            raise RuntimeError("Could not create LuaJIT state")
        try:
            self.lib.luaL_openlibs(state)
            # JSON string syntax is also valid for these Lua path strings.
            program = (r"""
local util = require('jit.util')
local chunk, message = loadfile(FILE)
if not chunk then return 'ERROR\t' .. message end
local rows = {}
local function inspect(fn, root)
    local info = util.funcinfo(fn)
    rows[#rows+1] = table.concat({info.linedefined, info.lastlinedefined,
        info.stackslots, info.upvalues, info.params, info.bytecodes,
        root and 1 or 0}, '\t')
    for index=1,info.gcconsts do
        local child = util.funck(fn, -index)
        if type(child) == 'proto' then inspect(child, false) end
    end
end
inspect(chunk, true)
return table.concat(rows, '\n')
""".replace("FILE", json.dumps(path.as_posix()))).encode()
            result = self.lib.luaL_loadbuffer(state, program, len(program), b"@lua-limit-audit")
            if not result:
                result = self.lib.lua_pcall(state, 0, 1, 0)
            size = ctypes.c_size_t()
            pointer = self.lib.lua_tolstring(state, -1, ctypes.byref(size))
            value = ctypes.string_at(pointer, size.value).decode("utf-8", "replace") if pointer else "No result"
            if result or value.startswith("ERROR\t"):
                return {"error": value.removeprefix("ERROR\t")}
            keys = ("line", "last_line", "slots", "upvalues", "parameters", "bytecodes", "chunk")
            functions = [dict(zip(keys, map(int, row.split("\t")))) for row in value.splitlines()]
            return {"functions": functions, "max_slots": max(f["slots"] for f in functions),
                    "max_upvalues": max(f["upvalues"] for f in functions),
                    "chunk_slots": functions[0]["slots"], "lines": len(path.read_text(encoding="utf-8-sig").splitlines())}
        finally:
            self.lib.lua_close(state)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library")
    parser.add_argument("--report", type=Path, default=ROOT / "output/lua-module-audit/limits.json")
    parser.add_argument("--max-slots", type=int, default=180,
                        help="Project headroom budget (LuaJIT hard limit: 250 slots, 200 locals)")
    parser.add_argument("--max-upvalues", type=int, default=45,
                        help="Project headroom budget (LuaJIT hard limit: 60 upvalues)")
    args = parser.parse_args()
    compiler = Compiler(library_path(args.library))
    files = [ROOT / "main.lua", ROOT / "conf.lua", *sorted((ROOT / "src").rglob("*.lua"))]
    report = {"budgets": {"slots": args.max_slots, "upvalues": args.max_upvalues}, "files": {}}
    failures = []
    for path in files:
        name = path.relative_to(ROOT).as_posix()
        data = compiler.inspect(path)
        report["files"][name] = data
        if "error" in data:
            failures.append(f"{name}: {data['error']}")
        else:
            for fn in data["functions"]:
                if fn["slots"] > args.max_slots or fn["upvalues"] > args.max_upvalues:
                    failures.append(f"{name}:{fn['line']}: {fn['slots']} slots, {fn['upvalues']} upvalues")
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    top = sorted(((data.get("max_slots", 0), name, data) for name, data in report["files"].items()), reverse=True)[:12]
    for _, name, data in top:
        print(f"{name}: {data.get('chunk_slots', '?')} chunk slots; peak {data.get('max_slots', '?')} slots / {data.get('max_upvalues', '?')} upvalues")
    print(f"{'FAIL' if failures else 'PASS'}: {len(files)} files; "
          f"{sum(len(d.get('functions', [])) for d in report['files'].values())} compiled functions; "
          f"budgets {args.max_slots} slots / {args.max_upvalues} upvalues.")
    for failure in failures:
        print(failure, file=sys.stderr)
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
