"""Offline integration checks; invoke with HAX, generated config, context, skill tree."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HAX, CONFIG, CONTEXT, SKILLS = map(Path, sys.argv[1:5])
sys.argv[1:] = []


class PilotSmoke(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hax-smoke-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / "config" / "hax"
        self.config.mkdir(parents=True)
        shutil.copyfile(CONFIG, self.config / "config.json")
        shutil.copyfile(CONTEXT, self.config / "AGENTS.md")
        (self.config / "skills").symlink_to(SKILLS)
        self.work = self.root / "work"
        self.work.mkdir()
        self.trace = self.root / "transcript.txt"
        # Allowlisted environment: never inherit real provider/auth/debug settings.
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.root / "home"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "HAX_PROVIDER": "mock",
            "HAX_MODEL": "mock",
            "HAX_EFFORT": "",
            "HAX_TRANSCRIPT": str(self.trace),
            "HAX_CATALOG_REFRESH": "0",
            "HAX_KEEP_AWAKE": "off",
            "NO_COLOR": "1",
        }
        Path(self.env["HOME"]).mkdir()

    def run_mock(self, script, *args):
        fixture = self.root / "mock.txt"
        fixture.write_text(script, encoding="utf-8")
        self.env["HAX_MOCK_SCRIPT"] = str(fixture)
        result = subprocess.run(
            [str(HAX), "--json", *args, "offline smoke test"],
            env=self.env, cwd=self.work, text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        records = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(records[-1]["type"], "result")
        self.assertEqual(records[-1]["outcome"], "complete")
        return records

    def test_native_file_and_shell_tools(self):
        records = self.run_mock(
            'tool write {"path":"fixture.txt","content":"before\\n"}\nend-turn\n'
            'tool read {"path":"fixture.txt"}\nend-turn\n'
            'tool edit {"path":"fixture.txt","old_string":"before","new_string":"after"}\nend-turn\n'
            'tool bash {"command":"printf shell-ok"}\nend-turn\n'
            'text offline-ok\nend-turn\n'
        )
        self.assertEqual((self.work / "fixture.txt").read_text(), "after\n")
        outputs = [r["output"] for r in records if r.get("kind") == "tool_result"]
        self.assertEqual(len(outputs), 4)
        self.assertTrue(any("before" in o for o in outputs))
        self.assertTrue(any("shell-ok" in o for o in outputs))
        transcript = self.trace.read_text()
        self.assertIn("Ciel is a Deity", transcript)
        self.assertIn("hax-tools", transcript)
        self.assertIn("task_wait", transcript)
        self.assertIn("jujutsu", transcript)
        self.assertEqual(records[-1]["text"], "offline-ok")

    def test_bare_drops_global_context_and_skill_catalogue(self):
        with (self.config / "AGENTS.md").open("a") as output:
            output.write("\nPRIVATE_CONTEXT_SENTINEL_94\n")
        self.run_mock("text bare-ok\nend-turn\n", "--bare")
        transcript = self.trace.read_text()
        self.assertNotIn("PRIVATE_CONTEXT_SENTINEL_94", transcript)
        self.assertNotIn("HAX pilot capability inventory", transcript)
        self.assertIn("old_string", transcript)  # Tools remain available.

    def test_configuration_and_skill_contract(self):
        settings = json.loads(CONFIG.read_text())
        self.assertEqual(settings["provider"], "codex")
        self.assertEqual(settings["notify"], "off")
        self.assertEqual(settings["catalog"]["refresh"], "0")
        self.assertEqual(settings["session_retention_days"], 0)
        self.assertNotIn("presets", settings)  # No unported advertised roles.
        self.assertEqual(
            {p.name for p in SKILLS.iterdir()},
            {"hax-tools", "browser", "nix", "jujutsu"},
        )
        for folder in SKILLS.iterdir():
            text = (folder / "SKILL.md").read_text()
            self.assertTrue(text.startswith("---\n"), folder)
            self.assertIn(f"name: {folder.name}\n", text, folder)


if __name__ == "__main__":
    unittest.main()
