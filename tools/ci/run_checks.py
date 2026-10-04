#!/usr/bin/env python3
"""Headless CI adapter for the existing suites; never treats exit zero alone as a pass."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "ci-results"
CAMPAIGN_MARKERS = {
    "session": r"ARCHIPELAGO SESSION: \d+ assertions, 0 failures",
    "restore-ui": r"RESTORE UI: \d+ assertions, 0 failures",
    "end-to-end": r"ARCHIPELAGO E2E: \d+ assertions, 0 failures; 108/108",
    "geometry-rules": r"Geometry rule suite: 0 failures, 18 action-completed levels",
    "fractions-rules": r"FRACTIONS PASS \d+ checks",
    "observatory-rules": r"OBSERVATORY RULES: 0 failures",
    "observatory-boundaries": r"OBSERVATORY ADVERSARIAL: 0 failures",
    "observatory-voyage": r"OBSERVATORY VOYAGE: \d+ independently certified networks; 0 failures",
    "campaign-headless": r"CAMPAIGN UI: \d+ assertions, 0 failures; headless",
}


def validate_output(output: str, returncode: int, markers: list[str]) -> list[str]:
    problems = []
    if returncode:
        problems.append(f"Process exited {returncode}")
    problems.extend(line for line in output.splitlines()
                    if "ERROR:" in line or "SCRIPT ERROR" in line)
    for marker in markers:
        if re.search(marker, output, re.MULTILINE) is None:
            problems.append(f"Missing completion marker: {marker}")
    for passed, total in re.findall(r"(\d+)/(\d+) PASS", output):
        if int(total) == 0 or passed != total:
            problems.append(f"Incomplete assertions: {passed}/{total} PASS")
    return problems


def run_case(name: str, command: list[str], environment: dict[str, str],
             markers: list[str], timeout: int = 180) -> dict:
    print(f"::group::{name}", flush=True)
    started = time.monotonic()
    try:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=os.name != "nt")
        try:
            output, _ = process.communicate(timeout=timeout)
            code = process.returncode
            problems = validate_output(output, code, markers)
        except subprocess.TimeoutExpired:
            # Aggregate Python suites spawn Godot. Kill/reap the whole group so a
            # timed-out child cannot keep the pipe open or affect later tests.
            try:
                if os.name == "nt":
                    process.kill()
                else:
                    os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            output, _ = process.communicate()
            code, problems = -1, [f"Timed out after {timeout}s; process group stopped"]
    except OSError as error:
        output, code, problems = str(error), -1, [str(error)]
    log = OUT / f"{name}.log"
    log.write_text("$ " + shlex.join(command) + "\n" + output, encoding="utf-8")
    print(output, end="" if output.endswith("\n") else "\n", flush=True)
    print(f"{'FAIL' if problems else 'PASS'} {name}", flush=True)
    for problem in problems:
        print(problem, flush=True)
    print("::endgroup::", flush=True)
    return {"name": name, "passed": not problems, "returncode": code,
            "seconds": round(time.monotonic() - started, 2),
            "errors": problems, "log": log.name, "command": command}


def check_campaign_reports() -> list[str]:
    directory = ROOT / "docs/playtest/archipelago"
    try:
        reports = json.loads((directory / "latest-checks.json").read_text())
        if len(reports) != len(CAMPAIGN_MARKERS) or {r["name"] for r in reports} != set(CAMPAIGN_MARKERS):
            return ["Campaign report does not contain exactly the nine expected checks"]
        problems = []
        for report in reports:
            name = report["name"]
            if not report.get("passed") or report.get("returncode") != 0 or report.get("errors"):
                problems.append(f"Campaign report failed: {name}")
            problems.extend(validate_output((directory / f"{name}.log").read_text(),
                                            report["returncode"], [CAMPAIGN_MARKERS[name]]))
        return problems
    except (OSError, ValueError, KeyError, TypeError) as error:
        return [f"Invalid or missing campaign report: {error}"]


def generated_reports():
    for folder in ("forest-release", "workshop-chapter-hub", "archipelago"):
        source = ROOT / "docs/playtest" / folder
        for pattern in ("*.log", "verification*.json", "latest-checks.json", "end-to-end.json"):
            yield from ((folder, path) for path in source.glob(pattern))


def clear_generated_reports() -> None:
    # A failure must not publish a tracked historical PASS report as fresh evidence.
    for _, path in generated_reports():
        path.unlink()
    # E2E recreates this synthetic fixture before the campaign UI consumes it.
    (ROOT / "docs/playtest/archipelago/completed-fixture.json").unlink(missing_ok=True)


def collect_reports() -> None:
    # Only explicit synthetic test reports/logs, never a user's profile or the checkout.
    for folder, path in generated_reports():
        destination = OUT / "reports" / folder
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination / path.name)


def save_results(results: list[dict]) -> None:
    (OUT / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write("\n### Godot headless checks\n\n")
            for record in results:
                stream.write(f"- {'PASS' if record['passed'] else 'FAIL'}: {record['name']}\n")
            stream.write("\nLinux / Godot 4.6.3 only. Native graphics, touch, audio, macOS, "
                         "Godot 4.7, and human playtesting are separate checks.\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--import-only", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot:
        parser.error("Install Godot 4.6.3 and put godot on PATH (or set GODOT)")
    results = []
    with tempfile.TemporaryDirectory(prefix="mathgame-ci-") as temporary:
        environment = os.environ.copy()
        environment["GODOT"] = godot
        environment["PATH"] = str(Path(godot).resolve().parent) + os.pathsep + environment["PATH"]
        for kind in ("CACHE", "CONFIG", "DATA"):
            path = Path(temporary) / kind.lower()
            path.mkdir()
            environment[f"XDG_{kind}_HOME"] = str(path)
        if args.import_only:
            record = run_case("import", [godot, "--headless", "--audio-driver", "Dummy",
                                         "--path", str(ROOT), "--editor", "--import"],
                              environment, [], timeout=600)
            results.append(record)
            (OUT / "import-result.json").write_text(json.dumps(record, indent=2) + "\n")
        else:
            clear_generated_reports()
            # Use the existing forest runner's source-stability and assertion checks.
            results.append(run_case("forest", [sys.executable, "tests/forest/run_checks.py"],
                                    environment, [r"^PASS .*_test\.gd:"], timeout=1800))
            for group, prefix, title in (("market", "mk", "MARKET MK"), ("workshop", "gw", "GW")):
                for number in range(1, 19):
                    ident = f"{prefix}{number:02}"
                    marker = (rf"{title}{number:02} RULES \d+/\d+ PASS" if group == "market"
                              else rf"{title}{number:02} RULES: [1-9]\d* checks, 0 failures")
                    results.append(run_case(ident, [godot, "--headless", "--audio-driver", "Dummy",
                                                   "--path", str(ROOT), "--script", f"tests/{group}/{ident}_test.gd"],
                                            environment, [marker]))
            results.append(run_case("market-hub", [godot, "--headless", "--path", str(ROOT),
                                                    "--script", "tests/market/hub_test.gd"],
                                    environment, [r"MARKET HUB RULES \d+/\d+ PASS"]))
            results.append(run_case("workshop-hub", [sys.executable, "tests/workshop/run_hub_checks.py", "--headless"],
                                    environment, [r"^rules PASS [1-9]\d*", r"^headless PASS [1-9]\d*"], timeout=400))
            campaign = run_case("archipelago", [sys.executable, "tests/archipelago/run_checks.py"],
                                environment, [rf"^{name} PASS$" for name in CAMPAIGN_MARKERS], timeout=1800)
            campaign["errors"].extend(check_campaign_reports())
            campaign["passed"] = not campaign["errors"]
            results.append(campaign)
            for name, script, marker in (
                ("geometry-alternatives", "tests/geometry/test_alternatives.gd",
                 r"Geometry independent alternatives: [1-9]\d* accepted; [1-9]\d* derived boss branches; 0 failures"),
                ("fractions-saves", "tests/fractions/session_test.gd", r"FRACTIONS ALL18 REPOSITORY PASS"),
            ):
                results.append(run_case(name, [godot, "--headless", "--path", str(ROOT), "--script", script],
                                        environment, [marker]))
            collect_reports()
    save_results(results)
    return 0 if results and all(record["passed"] for record in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
