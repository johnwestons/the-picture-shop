from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_lua_limits import Compiler, library_path


class LuaLimitsAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            cls.compiler = Compiler(library_path(None))
        except (RuntimeError, OSError) as error:
            raise unittest.SkipTest(str(error))

    def inspect(self, text):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "fixture.lua"
            file.write_text(text, encoding="utf-8")
            return self.compiler.inspect(file)

    def test_audit_does_not_execute_the_source(self):
        result = self.inspect('error("This source must never execute")\nreturn function() return 7 end')
        self.assertNotIn("error", result)
        self.assertEqual(len(result["functions"]), 2)

    def test_nested_capture_pressure_is_reported(self):
        values = [f"v{index}" for index in range(46)]
        source = "\n".join(f"local {name} = 1" for name in values)
        source += "\nreturn function() return function() return " + " + ".join(values) + " end end"
        result = self.inspect(source)
        self.assertEqual(result["max_upvalues"], 46)
        self.assertEqual(len(result["functions"]), 3)

    def test_local_variable_overflow_is_a_compile_error(self):
        result = self.inspect("\n".join(f"local v{index} = 1" for index in range(201)))
        self.assertIn("error", result)
        self.assertIn("local variables", result["error"])

    def test_capture_overflow_is_a_compile_error(self):
        values = [f"v{index}" for index in range(61)]
        source = "\n".join(f"local {name} = 1" for name in values)
        source += "\nreturn function() return " + " + ".join(values) + " end"
        result = self.inspect(source)
        self.assertIn("error", result)
        self.assertIn("upvalues", result["error"])


if __name__ == "__main__":
    unittest.main()
