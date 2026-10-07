"""Compare two completed art-only terrain reports; never run Godot.

Example:
  python game/tests/compare_raid_performance.py --terrain-before BEFORE.json
    --terrain-after AFTER.json --probe game/tests/benchmark_raid_terrain.gd
    --expected-probe-sha256 SHA --before-pack-sha256 SHA --after-pack-sha256 SHA
    --output-dir tools/review/phase4-terrain-comparison

Pack hashes are supplied, previously verified provenance, not rehashed here.
This avoids reading large executables while the operator runs GPU benchmarks.
No percentile is pooled or averaged from scenario percentiles.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
from typing import Any

BIOMES = dict(zip((3, 7, 11, 15, 19, 23, 27, 31),
                  ("coral", "convoy", "storm", "jade", "volcanic", "dusk", "arctic", "final")))
EXPECTED_KEYS = {(mission, view, p) for mission in BIOMES
                 for view in ("coast", "plateau") for p in (0, 1)}
ROOT_FIELDS = (
    "schema", "engine", "gpu", "cpu", "os", "quality", "requested_window",
    "actual_window", "root_visible_rect", "viewport", "duration_ticks_per_scenario",
    "warmup_ticks_per_scenario", "physics_hz", "vsync", "max_fps", "seed",
    "field_width", "field_length", "measured_scroll_distance", "terrain_rng_note",
    "method", "comparison_contract",
)
CASE_FIELDS = (
    "mission", "biome", "view", "pass", "viewport", "camera_position", "camera_size",
    "width", "length", "safe_x", "scroll_speed", "origin_z", "warmup_ticks",
)
STATE_FIELDS = ("physics_ticks", "state_signature", "state_samples")
METRICS = {"frame": "frame_intervals", "gpu": "gpu_completed_ms", "cpu_monitor": "cpu_process_ms"}
STAT_FIELDS = ("mean_ms", "p95_ms", "p99_ms", "max_ms", "samples", "over_16_67ms", "over_33_33ms")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def load_report(path: Path) -> tuple[dict[str, Any], dict[str, str]]:
    data = path.read_bytes()
    report = json.loads(data)
    if not isinstance(report, dict):
        raise ValueError(f"Report must be an object: {path}")
    return report, {"path": str(path.resolve()), "sha256": sha256(data)}


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def same_fields(before: dict, after: dict, fields: tuple, context: str, errors: list[str]) -> None:
    for field in fields:
        if field not in before or field not in after:
            errors.append(f"{context}: missing required field {field}")
        elif before[field] != after[field]:
            errors.append(f"{context}: {field} differs: {before[field]!r} != {after[field]!r}")


def index_report(report: dict, label: str, errors: list[str]) -> dict[tuple, dict]:
    require(report.get("failures") == [], f"{label}: nonempty/missing benchmark failures", errors)
    for field, expected in (("schema", 1), ("physics_hz", 60), ("warmup_ticks_per_scenario", 60),
                            ("vsync", False), ("max_fps", 0), ("seed", 1942),
                            ("field_width", 65.0), ("field_length", 220.0), ("measured_scroll_distance", 18.0)):
        require(report.get(field) == expected, f"{label}: {field} differs from the standard art fixture", errors)
    require(isinstance(report.get("duration_ticks_per_scenario"), int)
            and report["duration_ticks_per_scenario"] >= 360,
            f"{label}: measured duration is below six seconds or unreported", errors)
    require(report.get("quality") in (0, 1, 2), f"{label}: invalid quality", errors)
    cases = report.get("scenarios", [])
    require(isinstance(cases, list) and len(cases) == 32, f"{label}: expected exactly 32 scenarios", errors)
    indexed = {}
    for case in cases if isinstance(cases, list) else []:
        if not isinstance(case, dict):
            errors.append(f"{label}: scenario must be an object")
            continue
        key = (case.get("mission"), case.get("view"), case.get("pass"))
        require(key not in indexed, f"{label}: duplicate scenario {key}", errors)
        indexed[key] = case
        require(case.get("biome") == BIOMES.get(key[0]), f"{label} {key}: unexpected biome", errors)
        require(case.get("viewport") == report.get("viewport"), f"{label} {key}: viewport differs from root parameters", errors)
        require(case.get("width") == report.get("field_width") and case.get("length") == report.get("field_length"),
                f"{label} {key}: terrain dimensions differ from root parameters", errors)
        require(case.get("camera_size") == 21.0 and case.get("camera_position") == "(0.0, -3.2, 0.0)",
                f"{label} {key}: camera differs from the standard low-flight fixture", errors)
        require(case.get("node_counts", {}).get("collision_objects") == 0,
                f"{label} {key}: art rig contains collisions or lacks this count", errors)
        memory_before = case.get("before_memory", {})
        memory_after = case.get("after_dispose_memory", {})
        require("nodes" in memory_before and memory_after.get("nodes") == memory_before["nodes"],
                f"{label} {key}: rig node count was not restored", errors)
        require("orphan_nodes" in memory_before and "orphan_nodes" in memory_after
                and memory_after["orphan_nodes"] <= memory_before["orphan_nodes"],
                f"{label} {key}: orphan nodes grew or are unreported", errors)
        measured = case.get("measurement", {})
        require(measured.get("physics_ticks") == report.get("duration_ticks_per_scenario"),
                f"{label} {key}: incomplete measurement ticks", errors)
        require(case.get("warmup_ticks") == report.get("warmup_ticks_per_scenario"),
                f"{label} {key}: incomplete warmup ticks", errors)
        for metric in METRICS.values():
            stats = measured.get(metric, {})
            require(all(field in stats for field in STAT_FIELDS),
                    f"{label} {key}: incomplete {metric} statistics", errors)
            if not all(field in stats for field in STAT_FIELDS):
                continue
            require(all(isinstance(stats[field], (int, float)) and math.isfinite(stats[field])
                        and stats[field] >= 0 for field in STAT_FIELDS),
                    f"{label} {key}: invalid {metric} numbers", errors)
            require(stats["samples"] > 0, f"{label} {key}: {metric} has no samples", errors)
            require(stats["p95_ms"] <= stats["p99_ms"] <= stats["max_ms"]
                    and stats["mean_ms"] <= stats["max_ms"],
                    f"{label} {key}: inconsistent {metric} statistics", errors)
    require(set(indexed) == EXPECTED_KEYS, f"{label}: scenario keys differ from eight biomes x two views x two passes", errors)
    for mission in BIOMES:
        for view in ("coast", "plateau"):
            pair = (indexed.get((mission, view, 0)), indexed.get((mission, view, 1)))
            if all(pair):
                same_fields(pair[0].get("measurement", {}), pair[1].get("measurement", {}),
                            STATE_FIELDS, f"{label} M{mission} {view} repeat", errors)
    entry = report.get("entry_memory", {})
    final = report.get("after_fixture_dispose_memory", {})
    require("nodes" in entry and final.get("nodes") == entry["nodes"],
            f"{label}: final fixture node count was not restored", errors)
    require("orphan_nodes" in entry and "orphan_nodes" in final and final["orphan_nodes"] <= entry["orphan_nodes"],
            f"{label}: final orphan count grew or is unreported", errors)
    return indexed


def template_provenance(repo: Path) -> list[dict]:
    records = []
    for relative in ("game/scenes/main.tscn", "game/scripts/campaign/materials.gd"):
        current = (repo / relative).read_bytes()
        result = subprocess.run(["git", "show", f"HEAD:{relative}"], cwd=repo,
                                capture_output=True, check=True)
        head = result.stdout
        # Source identity is checked independent of checkout LF/CRLF conversion.
        normalised_current = current.replace(b"\r\n", b"\n")
        normalised_head = head.replace(b"\r\n", b"\n")
        records.append({"path": relative, "current_file_sha256": sha256(current),
                        "head_blob_sha256": sha256(head),
                        "normalised_lf_content_sha256": sha256(normalised_current),
                        "head_matches_current_after_lf_normalisation": normalised_current == normalised_head})
    return records


def make_rows(before: dict, after: dict, before_index: dict, after_index: dict,
              provenance: dict) -> list[dict]:
    rows = []
    for key in sorted(EXPECTED_KEYS):
        old, new = before_index[key], after_index[key]
        row = {"mission": key[0], "biome": old["biome"], "view": key[1], "pass": key[2],
               "before_build_id": before["build_id"], "after_build_id": after["build_id"],
               "before_report_sha256": provenance["before_report"]["sha256"],
               "after_report_sha256": provenance["after_report"]["sha256"],
               "shared_probe_sha256": provenance["shared_probe"]["sha256"],
               "before_pack_sha256_operator_verified": provenance["before_pack_sha256_operator_verified"],
               "after_pack_sha256_operator_verified": provenance["after_pack_sha256_operator_verified"]}
        for field in CASE_FIELDS:
            row[field] = old[field]
        row["physics_ticks"] = old["measurement"]["physics_ticks"]
        row["state_signature"] = old["measurement"]["state_signature"]
        for prefix, metric in METRICS.items():
            for stage, case in (("before", old), ("after", new)):
                for field in STAT_FIELDS:
                    row[f"{prefix}_{stage}_{field}"] = case["measurement"][metric][field]
            for field in ("mean_ms", "p95_ms", "p99_ms", "max_ms"):
                row[f"{prefix}_delta_{field}"] = row[f"{prefix}_after_{field}"] - row[f"{prefix}_before_{field}"]
        for stage, case in (("before", old), ("after", new)):
            for field in ("construction_ms", "triangles", "props", "configure_arguments", "layout_id"):
                row[f"{stage}_{field}"] = case[field]
            row[f"{stage}_gpu_zero_samples"] = case["measurement"]["gpu_zero_samples"]
            for field in ("nodes", "mesh_instances", "multimesh_groups", "collision_objects"):
                row[f"{stage}_{field}"] = case["node_counts"][field]
            for state in ("before_memory", "active_memory", "after_dispose_memory"):
                for field in ("engine_static_bytes", "render_estimated_bytes", "nodes", "resources", "orphan_nodes"):
                    row[f"{stage}_{state}_{field}"] = case[state][field]
        row["construction_delta_ms"] = new["construction_ms"] - old["construction_ms"]
        rows.append(row)
    return rows


def metric_synthesis(rows: list[dict], metric: str) -> dict:
    result = {}
    for stage in ("before", "after"):
        values = [row[f"{metric}_{stage}_p99_ms"] for row in rows]
        result[stage] = {
            "range_of_scenario_p99_ms": [min(values), max(values)],
            "largest_scenario_frame_or_monitor_ms": max(row[f"{metric}_{stage}_max_ms"] for row in rows),
            "sum_of_scenario_samples": sum(row[f"{metric}_{stage}_samples"] for row in rows),
            "sum_of_over_16_67ms_counts": sum(row[f"{metric}_{stage}_over_16_67ms"] for row in rows),
            "sum_of_over_33_33ms_counts": sum(row[f"{metric}_{stage}_over_33_33ms"] for row in rows),
        }
    deltas = [row[f"{metric}_delta_p99_ms"] for row in rows]
    result["range_of_paired_scenario_p99_deltas_ms"] = [min(deltas), max(deltas)]
    result["paired_scenario_p99_lower_equal_higher_counts"] = {
        "lower": sum(delta < 0 for delta in deltas), "equal": sum(delta == 0 for delta in deltas),
        "higher": sum(delta > 0 for delta in deltas),
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--terrain-before", type=Path, required=True)
    parser.add_argument("--terrain-after", type=Path, required=True)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--expected-probe-sha256", required=True)
    parser.add_argument("--before-pack-sha256", default="NOT_SUPPLIED")
    parser.add_argument("--after-pack-sha256", default="NOT_SUPPLIED")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    errors: list[str] = []
    for label, pack_hash in (("before", args.before_pack_sha256), ("after", args.after_pack_sha256)):
        require(pack_hash == "NOT_SUPPLIED" or len(pack_hash) == 64
                and all(character in "0123456789ABCDEFabcdef" for character in pack_hash),
                f"Invalid supplied {label} pack SHA256", errors)
    before, before_source = load_report(args.terrain_before)
    after, after_source = load_report(args.terrain_after)
    probe_hash = sha256(args.probe.read_bytes())
    require(probe_hash == args.expected_probe_sha256.upper(), "External probe differs from the operator's recorded source hash", errors)
    templates = template_provenance(args.repo_root)
    for template in templates:
        require(template["head_matches_current_after_lf_normalisation"],
                f"Lighting/camera source differs from baseline HEAD: {template['path']}", errors)
    provenance = {"before_report": before_source, "after_report": after_source,
                  "shared_probe": {"path": str(args.probe.resolve()), "sha256": probe_hash,
                                   "expected_operator_run_sha256": args.expected_probe_sha256.upper()},
                  "before_pack_sha256_operator_verified": args.before_pack_sha256.upper(),
                  "after_pack_sha256_operator_verified": args.after_pack_sha256.upper(),
                  "source_git_head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=args.repo_root,
                                                     capture_output=True, text=True, check=True).stdout.strip(),
                  "camera_lighting_source_templates": templates,
                  "provenance_limit": "Pack hashes/run probe identity are previously verified operator provenance. This tool hashes the reports, current probe and unchanged HEAD/current templates; it does not inspect or rerun the packs."}
    same_fields(before, after, ROOT_FIELDS, "Root protocol", errors)
    before_index = index_report(before, "Before", errors)
    after_index = index_report(after, "After", errors)
    for key in sorted(set(before_index) & set(after_index)):
        same_fields(before_index[key], after_index[key], CASE_FIELDS, f"Pair {key}", errors)
        same_fields(before_index[key].get("measurement", {}), after_index[key].get("measurement", {}),
                    STATE_FIELDS, f"Pair {key} deterministic path", errors)
    rows = [] if errors else make_rows(before, after, before_index, after_index, provenance)
    report = {"schema": 1, "comparable_recorded_protocol": not errors, "errors": errors,
              "provenance": provenance, "before_build_id": before.get("build_id"),
              "after_build_id": after.get("build_id"), "pair_count": len(rows),
              "recorded_protocol_before": {field: before.get(field) for field in ROOT_FIELDS},
              "checked_root_fields": ROOT_FIELDS, "checked_scenario_fields": CASE_FIELDS,
              "checked_deterministic_path_fields": STATE_FIELDS,
              "limits": [
                  "Art-only rig: no aircraft, DCA, HUD, collisions, input or combat. Whole-game FPS and difficulty are not measured.",
                  "32 matched scenarios at one quality, two 6-second measured passages per biome/view; not a long-duration or thermal/load-order controlled trial.",
                  "P95/P99 are compared per scenario. Ranges below are ranges of scenario percentiles, not pooled/global percentiles.",
                  "Rendering cadence/GPU completed times can lag; TIME_PROCESS can retain stale construction values and is not isolated or total CPU cost.",
                  "Camera position/size/path/viewport are recorded and compared. Rotation/projection/near/far/light properties are not recorded in JSON; unchanged HEAD/current source templates provide supplementary source evidence.",
                  "Rig construction and startup are separate costs and are not equivalent to a production gameplay-transition hitch.",
                  "Engine static/estimated graphics bytes are not process private RAM or physical VRAM; cached resources can remain. Cleanup does not establish absence of long-term leaks.",
                  "Geometry/layout/props/albedos intentionally differ between packs. No isolated shader causation or FPS guarantee is inferred.",
                  "Human visual inspection/listening is not performed by this analysis.",
              ], "comparative_metrics": {}, "cleanup": {
                  "before": before.get("after_fixture_dispose_memory"),
                  "after": after.get("after_fixture_dispose_memory")}}
    if rows:
        report["identical_physics_state_sample_pairs"] = sum(len(case["measurement"]["state_samples"]) for case in before_index.values())
        report["comparative_metrics"] = {metric: metric_synthesis(rows, metric) for metric in METRICS}
        report["construction_ms"] = {
            stage + "_range": [min(row[f"{stage}_construction_ms"] for row in rows),
                               max(row[f"{stage}_construction_ms"] for row in rows)]
            for stage in ("before", "after")}
        report["construction_ms"]["paired_delta_range"] = [min(row["construction_delta_ms"] for row in rows),
                                                             max(row["construction_delta_ms"] for row in rows)]
        report["startup_asset_load_ms"] = {"before": before["startup_asset_load_ms"],
                                             "after": after["startup_asset_load_ms"]}
    args.output_dir.mkdir(parents=True, exist_ok=True)
    summary_path = args.output_dir / "terrain-comparison.json"
    csv_path = args.output_dir / "terrain-comparison-32-pairs.csv"
    summary_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]) if rows else ["comparison_rejected"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"Terrain comparison: {len(rows)} pairs; {len(errors)} errors; {summary_path}")
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"Performance analysis failed: {error}", file=sys.stderr)
        raise SystemExit(1)
