"""Summarize an owned-process observer report, retaining limits of sampled RAM."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import statistics


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def stamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def summarize(process_path, engine_path):
    report, engine = read(process_path), read(engine_path)
    errors = []
    if report.get("state") != "completed" or report.get("errors") or report.get("cleanup_errors"):
        errors.append("Observer did not complete cleanly")
    if engine.get("failures") != []:
        errors.append("Engine report has failures or no failure status")
    if len(engine.get("passes", [])) != report["parameters"]["repeats"]:
        errors.append("Incomplete engine pass count")
    rows = []
    for sample in report["samples"]:
        primary = sample.get("primary_engine_pid")
        candidates = [row for row in sample["processes"] if row["pid"] == primary and row["is_engine_candidate"]]
        if len(candidates) > 1:
            errors.append("Ambiguous primary renderer sample")
        for row in candidates:
            rows.append({**row, "timestamp": stamp(row.get("sampled_utc", sample["utc"]))})
    pids = {row["pid"] for row in rows}
    if len(pids) != 1:
        errors.append("Expected exactly one sampled renderer PID")
    if not rows:
        raise ValueError("No renderer samples")
    for process in report["processes"]:
        if process["exit_code"] != 0 or process["termination_requested"]:
            errors.append(f"Unclean process termination: {process['pid']}")
    windows = []
    if engine.get("kind") == "persistent_app_multi_mission_endurance":
        ranges = [(f"pass-{p['pass']:02d}-m{p['mission']:02d}-retry-{p['retry']}",
                   p["idle_start_unix_s"], p["idle_end_unix_s"]) for p in engine["passes"]]
        ranges.append(("final-app-disposed", *engine["final_idle_window_unix_s"]))
        for label, start, end in ranges:
            selected = [r for r in rows if start + .05 <= r["timestamp"] <= end - .05 and "sampled_utc" in r]
            if not selected:
                errors.append(f"No precisely timestamped sample in settled window: {label}")
                continue
            windows.append({"window": label, "samples": len(selected),
                            "private_bytes_min": min(r["private_memory_bytes"] for r in selected),
                            "private_bytes_max": max(r["private_memory_bytes"] for r in selected),
                            "private_bytes_median": statistics.median(r["private_memory_bytes"] for r in selected),
                            "working_set_bytes_median": statistics.median(r["working_set_bytes"] for r in selected)})
    gaps = [b["timestamp"] - a["timestamp"] for a, b in zip(rows, rows[1:])]
    if any(gap <= 0 for gap in gaps):
        errors.append("Non-monotonic wall clock samples")
    return {"schema": 1, "errors": errors, "renderer_pids": sorted(pids),
            "sample_count": len(rows), "observer_seconds": report["observer_wall_seconds"],
            "observed_private_bytes_peak": max(r["private_memory_bytes"] for r in rows),
            "observed_working_set_bytes_peak": max(r["working_set_bytes"] for r in rows),
            "sample_gap_median_s": statistics.median(gaps) if gaps else None,
            "sample_gap_max_s": max(gaps) if gaps else None,
            "settled_windows": windows,
            "engine_cleanup": [{"pass": p["pass"], "memory": p.get("after_probe_release_memory", p["after_dispose_memory"])} for p in engine["passes"]],
            "engine_final_memory": engine["final_memory"],
            "source_hashes": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [process_path, engine_path]},
            "limits": "Private bytes are committed private memory, not resident RAM; working set includes shared pages. Peaks are sampled, not guaranteed lifetime peaks. Engine/render monitors are distinct, and physical VRAM is not measured. Settled windows use per-process timestamps with 50 ms edge margins; old reports without windows do not establish private RAM after cleanup. No leak diagnosis, human gameplay, other hardware or FPS guarantee follows."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--process", type=Path, required=True)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = summarize(args.process, args.engine)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"errors": result["errors"], "samples": result["sample_count"], "settled_windows": len(result["settled_windows"])}))
    raise SystemExit(1 if result["errors"] else 0)
