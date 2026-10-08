"""Compare paired full-mission reports; no inference of human playability or GPU causality."""
import argparse
import hashlib
import json
from pathlib import Path


def read(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate key {key} in {path}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))


def compare(before, after):
    errors, pairs, hashes = [], [], {}
    reports = []
    for path in (before, after):
        summary = read(path)
        hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        if summary.get("failures") != []:
            errors.append(f"{path}: missing or nonempty failures")
        passes = summary.get("passes", [])
        if not passes:
            errors.append(f"{path}: no completed passes")
        details = []
        for index, item in enumerate(passes):
            detail_path = path.parent / item["details_file"]
            detail = read(detail_path)
            hashes[str(detail_path)] = hashlib.sha256(detail_path.read_bytes()).hexdigest()
            for key in ("pass", "physics_ticks", "finished_tick", "input_signature", "state_signature", "result", "gameplay", "gpu_ms"):
                if key not in detail or detail[key] != item.get(key):
                    errors.append(f"{path} pass {index}: detail/summary mismatch: {key}")
            samples = detail.get("state_samples", [])
            if len(samples) != summary.get("duration_ticks", 0) // 60:
                errors.append(f"{path} pass {index}: incomplete state history")
            if [sample.get("tick") for sample in samples] != list(range(60, summary["duration_ticks"] + 1, 60)):
                errors.append(f"{path} pass {index}: incorrect state sample ticks")
            if detail.get("physics_ticks") != summary.get("duration_ticks") or detail.get("finished_tick", -1) < 0:
                errors.append(f"{path} pass {index}: incomplete mission")
            if index and samples != details[0].get("state_samples"):
                errors.append(f"{path} pass {index}: replay state diverges within version")
            details.append(detail)
        reports.append((summary, details))
    old, new = reports
    for key in ("engine", "gpu", "cpu", "os", "mission", "quality", "resolution", "physics_hz", "vsync", "player_invulnerable", "duration_ticks", "rng_seed", "audio_rng_seed"):
        if key not in old[0] or key not in new[0] or old[0][key] != new[0][key]:
            errors.append(f"Protocol mismatch or missing field: {key}")
    if len(old[1]) != len(new[1]):
        errors.append("Different pass counts")
    for index, (a, b) in enumerate(zip(old[1], new[1])):
        changed = [key for key in ("cache", "viewport", "physics_ticks", "finished_tick", "input_signature", "state_signature", "state_samples", "result")
                   if key not in a or key not in b or a[key] != b[key]]
        if changed:
            errors.append(f"Paired pass {index}: gameplay/protocol differs: {changed}")
        pairs.append({"pass": index, "changed_fields": changed,
                      "before": {key: a[key] for key in ("gameplay", "gpu_ms", "phases", "launch_ms", "init_ms", "after_dispose_memory")},
                      "after": {key: b[key] for key in ("gameplay", "gpu_ms", "phases", "launch_ms", "init_ms", "after_dispose_memory")}})
    return {"schema": 1, "matched": not errors, "errors": errors, "pairs": pairs, "source_hashes": hashes,
            "limits": "Recorded states only; not every internal state. Audio driver and pack/probe identity require the launch manifest. No hardware cache/thermal control, causal shader attribution, averaged percentiles or human playability claim."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = compare(args.before, args.after)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        result = {"matched": False, "errors": [str(exc)]}
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"matched": result["matched"], "errors": result["errors"]}))
    raise SystemExit(0 if result["matched"] else 1)
