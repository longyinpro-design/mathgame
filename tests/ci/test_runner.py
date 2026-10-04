"""Fast tests for the CI adapter; these do not launch Godot."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

path = Path(__file__).resolve().parents[2] / "tools/ci/run_checks.py"
spec = importlib.util.spec_from_file_location("ci_runner", path)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class OutputValidationTests(unittest.TestCase):
    def test_complete_success(self):
        self.assertEqual(runner.validate_output("RULES 8/8 PASS\n", 0, [r"RULES \d+/\d+ PASS"]), [])

    def test_zero_exit_with_engine_error_fails(self):
        self.assertTrue(runner.validate_output("ERROR: Failed loading resource\nDONE", 0, ["DONE"]))

    def test_zero_exit_with_script_error_fails(self):
        self.assertTrue(runner.validate_output("SCRIPT ERROR: Assertion failed\nDONE", 0, ["DONE"]))

    def test_missing_completion_fails(self):
        self.assertTrue(runner.validate_output("started", 0, ["DONE"]))

    def test_partial_assertions_fail(self):
        self.assertTrue(runner.validate_output("RULES 7/8 PASS", 0, ["RULES"]))

    def test_zero_assertions_fail(self):
        self.assertTrue(runner.validate_output("RULES 0/0 PASS", 0, ["RULES"]))

    def test_process_failure_is_not_hidden(self):
        self.assertTrue(runner.validate_output("DONE", 1, ["DONE"]))

    @unittest.skipIf(runner.os.name == "nt", "Linux process-group behavior")
    def test_timeout_stops_and_reaps_descendants(self):
        process = Mock(pid=1234)
        process.communicate.side_effect = [subprocess.TimeoutExpired(["fake"], 1), ("partial output", None)]
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(runner, "OUT", Path(directory)), \
                 patch.object(runner.subprocess, "Popen", return_value=process) as spawn, \
                 patch.object(runner.os, "killpg") as kill:
                result = runner.run_case("timeout", ["fake"], {}, ["DONE"], timeout=1)
                self.assertFalse(result["passed"])
                self.assertIn("process group stopped", result["errors"][0])
                self.assertTrue(spawn.call_args.kwargs["start_new_session"])
                kill.assert_called_once_with(1234, runner.signal.SIGKILL)
                self.assertEqual(process.communicate.call_count, 2)


if __name__ == "__main__":
    unittest.main()
