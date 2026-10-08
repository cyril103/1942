#!/usr/bin/env python3
"""Compare the 36 posed readability fixtures without rendering or changing images.

Standard library only. --before and --after accept captures.json or its directory.
Manifest schema 1 and 2 are supported. Exit 0 means the posed scenarios and PNG
inventories/dimensions match, allowing only the six specified flare transitions;
it does not mean artistic acceptance, executable identity, or gameplay validation.
"""

from __future__ import annotations

import argparse
from collections import Counter
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zlib


BACKGROUND_CASES = ("dark-ocean", "foam", "sand", "snow", "vegetation")
CONTACT_CASES = (
    "feedback-ability", "game-over", "hierarchy", "mobile-announce",
    "mobile-fire", "mobile-move", "mobile-settle", "reinforcement",
)
DIMENSIONS = {"720": (1280, 720), "1080": (1920, 1080)}
EXPECTED_FILES = frozenset(
    [f"background-{case}-{effect}-{size}.png"
     for case in BACKGROUND_CASES for effect in ("clear", "explosion")
     for size in DIMENSIONS]
    + [f"contacts-{case}-{size}.png"
       for case in CONTACT_CASES for size in DIMENSIONS]
)
FLARE_FILES = frozenset(
    f"contacts-mobile-{phase}-{size}.png"
    for phase in ("announce", "move", "settle") for size in DIMENSIONS
)
MOBILE_CASES = {
    "announce": (13, 1, True, Decimal("0")),
    "move": (61, 2, False, Decimal("0")),
    "settle": (116, 3, False, Decimal("0")),
    "fire": (159, 0, True, Decimal("0.128095238095238")),
}
MOBILE_ID = "volcanic/m01"
HUD_METHODS = frozenset({
    "_draw_ground_contacts", "_ground_label_reservations", "_draw_mobile_motion_hint",
})
SOURCE_RESOURCES = {
    "res://scripts/campaign/ground_target.gd": "Script",
    "res://scripts/campaign/hud.gd": "Script",
    "res://shaders/enemy_bullet.gdshader": "Shader",
    "res://shaders/ground_target_fire.gdshader": "Shader",
    "res://shaders/tracer.gdshader": "Shader",
}
RESOURCE_ORIGIN = "resource_representation_not_exact_source_or_bytecode"
FILESYSTEM_ORIGIN = "accessible_filesystem_text_not_runtime_identity"
UNIFORM_FIELDS = frozenset({"id", "mobile_phase", "flare_kind", "flare_visible"})

# These exact root keys are reported as information. All other keys, including
# unknown future keys, participate in the exact scenario comparison.
CAPTURE_INFO = frozenset({
    "build", "source_hashes", "memory", "production_signature",
    "runtime_provenance", "filesystem_text_diagnostics",
})
TOP_INFO = frozenset({
    "build", "source_hashes", "memory", "initial_memory",
    "after_dispose_memory", "production_signature", "runtime_provenance",
    "filesystem_text_diagnostics", "schema",
})
REQUIRED_CAPTURE = frozenset({
    "biome", "build", "camera_position", "camera_rotation", "camera_size",
    "cockpit_canvas_size", "engine_time_scale", "extraction", "file",
    "final_contacts", "fixture", "gameplay_internal_pixels", "memory",
    "mission", "mission_elapsed_fixture", "physical_png_pixels", "play_rect",
    "player_position", "player_visual_altitude", "pools", "quality",
    "requested_window_pixels", "root_viewport_pixels_reported",
    "sea_manual_ticks", "sea_scroll_distance", "seed", "source_hashes",
    "terrain_position", "terrain_props", "terrain_size", "terrain_triangles",
    "window_pixels_reported",
})
REQUIRED_TOP = frozenset({
    "after_dispose_memory", "audio", "build", "captures", "cpu", "engine",
    "failures", "font", "gpu", "human_review", "initial_memory",
    "input_isolation", "limits", "method", "os", "quality",
    "resolution_note", "schema", "seed", "shader_time",
})
LIMITATIONS = [
    "Posed production scenes and manually advanced controller snapshots; not a natural mission or playtest.",
    "Initial builtin shader TIME is unavailable; equality across processes is not established.",
    "No human recognition, continuous-motion, contrast, or artistic acceptance result.",
    "No gameplay damage, raycast, target viability, cadence, performance, or FPS proof.",
    "Physical PNG dimensions and internal gameplay viewport dimensions are separate measurements.",
    "Memory values are engine/static and graphics estimates, not Windows private bytes or physical VRAM.",
    "A source-candidate build marker does not identify an exported executable.",
    "Recorded source text hashes do not prove the identity of executable bytecode.",
]
MISSING = object()


def _reject_constant(value: str):
    raise ValueError(f"Non-finite JSON number refused: {value}")


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON object key refused: {key!r}")
        result[key] = value
    return result


def _path(parts) -> str:
    """Use JSON Pointer so resource names containing dots stay unambiguous."""
    return "/" + "/".join(str(p).replace("~", "~0").replace("/", "~1") for p in parts)


def _report_value(value):
    return {"missing": True} if value is MISSING else value


def _is_number(value) -> bool:
    return type(value) in (int, Decimal)


def _equal(left, right) -> bool:
    if _is_number(left) and _is_number(right):
        return left == right
    return type(left) is type(right) and left == right


def _differences(left, right, parts=()):
    if isinstance(left, dict) and isinstance(right, dict):
        for key in sorted(left.keys() | right.keys()):
            yield from _differences(left.get(key, MISSING), right.get(key, MISSING), parts + (key,))
    elif isinstance(left, list) and isinstance(right, list):
        if len(left) != len(right):
            yield parts + ("length",), len(left), len(right)
        for index, (a, b) in enumerate(zip(left, right)):
            yield from _differences(a, b, parts + (index,))
    elif not _equal(left, right):
        yield parts, left, right


def _error(report, code, *, side=None, file=None, path=None, **details):
    item = {"code": code, **details}
    if side is not None:
        item["side"] = side
    if file is not None:
        item["file"] = file
    if path is not None:
        item["path"] = path
    report["errors"].append(item)


def _manifest_location(argument) -> Path:
    path = Path(argument).resolve()
    return path / "captures.json" if path.is_dir() else path


def _load_manifest(path, side, report):
    try:
        raw = path.read_bytes()
        data = json.loads(
            raw.decode("utf-8-sig"), parse_float=Decimal,
            parse_constant=_reject_constant, object_pairs_hook=_unique_object,
        )
    except (OSError, UnicodeError, ValueError, RecursionError) as exc:
        _error(report, "invalid_manifest", side=side, message=str(exc))
        return None
    report["inputs"][side] = {
        "manifest": str(path), "manifest_sha256": hashlib.sha256(raw).hexdigest(),
        "png_directory": str(path.parent), "schema": data.get("schema") if isinstance(data, dict) else None,
    }
    if not isinstance(data, dict):
        _error(report, "invalid_manifest_root", side=side, expected="object")
        return None
    missing = sorted(REQUIRED_TOP - data.keys())
    if missing:
        _error(report, "missing_top_fields", side=side, fields=missing)
    if type(data.get("schema")) is not int or data["schema"] not in (1, 2):
        _error(report, "unsupported_schema", side=side, value=data.get("schema"))
    if data.get("failures") != []:
        _error(report, "capture_harness_failures", side=side, value=data.get("failures"))
    if not _equal(data.get("seed"), 1942) or not _equal(data.get("quality"), 1):
        _error(report, "unexpected_capture_settings", side=side, seed=data.get("seed"), quality=data.get("quality"))
    return data


def _capture_index(data, side, report):
    result = {}
    captures = data.get("captures")
    if not isinstance(captures, list):
        _error(report, "invalid_captures", side=side, expected="array")
        return result
    if len(captures) != 36:
        _error(report, "capture_count", side=side, expected=36, actual=len(captures))
    for index, capture in enumerate(captures):
        if not isinstance(capture, dict) or not isinstance(capture.get("file"), str):
            _error(report, "invalid_capture", side=side, index=index)
            continue
        name = capture["file"]
        if name in result:
            _error(report, "duplicate_capture_file", side=side, file=name, index=index)
            continue
        result[name] = capture
        missing = sorted(REQUIRED_CAPTURE - capture.keys())
        if missing:
            _error(report, "missing_capture_fields", side=side, file=name, fields=missing)
    missing = sorted(EXPECTED_FILES - result.keys())
    extra = sorted(result.keys() - EXPECTED_FILES)
    if missing or extra:
        _error(report, "capture_inventory", side=side, missing=missing, extra=extra)
    return result


def _png_information(directory, side, captures, report):
    result = {}
    try:
        # Include .PNG variants in inventory errors rather than silently ignoring them.
        inventory = {p.name for p in directory.iterdir() if p.suffix.lower() == ".png"}
    except OSError as exc:
        _error(report, "unreadable_png_directory", side=side, message=str(exc))
        return result
    missing = sorted(EXPECTED_FILES - inventory)
    extra = sorted(inventory - EXPECTED_FILES)
    if missing or extra:
        _error(report, "png_inventory", side=side, missing=missing, extra=extra)
    for name in sorted(EXPECTED_FILES):
        path = directory / name
        try:
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                header = stream.read(33)
                digest.update(header)
                byte_count = len(header)
                while chunk := stream.read(1024 * 1024):
                    digest.update(chunk)
                    byte_count += len(chunk)
        except OSError as exc:
            _error(report, "unreadable_png", side=side, file=name, message=str(exc))
            continue
        info = {"sha256": digest.hexdigest(), "bytes": byte_count, "dimensions": None, "ihdr_valid": False}
        result[name] = info
        if len(header) != 33 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[8:16] != b"\x00\x00\x00\rIHDR":
            _error(report, "invalid_png_ihdr", side=side, file=name)
            continue
        if zlib.crc32(header[12:29]) & 0xFFFFFFFF != struct.unpack(">I", header[29:33])[0]:
            _error(report, "png_ihdr_crc", side=side, file=name)
            continue
        width, height = struct.unpack(">II", header[16:24])
        info.update({"dimensions": [width, height], "ihdr_valid": True})
        expected = DIMENSIONS[name.rsplit("-", 1)[1][:-4]]
        if (width, height) != expected:
            _error(report, "png_dimensions", side=side, file=name, expected=list(expected), actual=[width, height])
        capture = captures.get(name)
        if capture is not None:
            for field in ("physical_png_pixels", "requested_window_pixels", "window_pixels_reported"):
                if not _equal(capture.get(field), [width, height]):
                    _error(report, "png_manifest_dimensions", side=side, file=name,
                           path=_path((field,)), manifest=capture.get(field), actual=[width, height])
    return result


def _validate_fixture(name, capture, side, top, report):
    for field, value in (("seed", 1942), ("quality", 1), ("sea_manual_ticks", 60),
                         ("mission_elapsed_fixture", Decimal("37")), ("engine_time_scale", Decimal("0.000001"))):
        if not _equal(capture.get(field), value):
            _error(report, "fixture_contract", side=side, file=name, path=_path((field,)),
                   expected=value, actual=capture.get(field))
    if capture.get("build") != top.get("build"):
        _error(report, "inconsistent_build_label", side=side, file=name,
               capture=capture.get("build"), manifest=top.get("build"))
    pools = capture.get("pools")
    if not isinstance(pools, dict):
        _error(report, "invalid_pools", side=side, file=name)
    else:
        for prefix, capacity in (("player", 96), ("enemy", 192), ("explosions", 18)):
            active = pools.get(prefix + "_active")
            if not _equal(pools.get(prefix + "_capacity"), capacity) or not _is_number(active) or not 0 <= active <= capacity or active != int(active):
                _error(report, "pool_contract", side=side, file=name, pool=prefix,
                       active=active, capacity=pools.get(prefix + "_capacity"), expected_capacity=capacity)
    fixture = capture.get("fixture")
    if not isinstance(fixture, dict):
        _error(report, "invalid_fixture", side=side, file=name)
        return
    projectiles = fixture.get("projectiles")
    if not isinstance(projectiles, dict):
        _error(report, "missing_projectile_fixture", side=side, file=name)
    else:
        explosions = "-explosion-" in name or name.startswith("contacts-feedback-ability-")
        for field, value in (("explosions", explosions), ("explosion_advance_ticks", 9 if explosions else 0),
                             ("explosion_age_seconds", Decimal("0.15") if explosions else Decimal("0"))):
            if not _equal(projectiles.get(field), value):
                _error(report, "effect_clock_contract", side=side, file=name,
                       path=_path(("fixture", "projectiles", field)), expected=value, actual=projectiles.get(field))
    contacts = capture.get("final_contacts")
    if not isinstance(contacts, list) or any(not isinstance(c, dict) for c in contacts):
        _error(report, "invalid_final_contacts", side=side, file=name)
        return
    if not name.startswith("contacts-mobile-"):
        return
    phase_name = name.split("-")[2]
    steps, phase, visible, warning_time = MOBILE_CASES[phase_name]
    mobile = fixture.get("mobile")
    selected = [contact for contact in contacts if contact.get("id") == MOBILE_ID]
    if not isinstance(mobile, dict) or mobile.get("id") != MOBILE_ID or len(selected) != 1:
        _error(report, "mobile_contact_identity", side=side, file=name,
               fixture_id=mobile.get("id") if isinstance(mobile, dict) else None, contact_count=len(selected))
        return
    kind = 1 if side == "before" or phase_name == "fire" else 2
    expected_mobile = {
        "controller_steps": steps, "expected_phase": phase, "phase": phase,
        "step_seconds": Decimal("0.0166666666666667"), "warning_time": warning_time,
        "salvo_remaining": 0, "flare_visible": visible, "flare_kind": kind,
    }
    expected_contact = {
        "mobile": True, "mobile_phase": phase, "warning_time": warning_time,
        "salvo_remaining": 0, "flare_visible": visible, "flare_kind": kind,
    }
    for section, actual, expected in (("fixture/mobile", mobile, expected_mobile),
                                      ("final_contacts/volcanic~1m01", selected[0], expected_contact)):
        for field, value in expected.items():
            if not _equal(actual.get(field), value):
                _error(report, "mobile_fixture_contract", side=side, file=name,
                       path=f"/{section}/{field}", expected=value, actual=actual.get(field))


def _flare_exception(name, parts, before, after, left, right):
    if name not in FLARE_FILES or not _equal(before, 1) or not _equal(after, 2):
        return False
    if parts == ("fixture", "mobile", "flare_kind"):
        return left["fixture"]["mobile"].get("id") == right["fixture"]["mobile"].get("id") == MOBILE_ID
    if len(parts) == 3 and parts[0] == "final_contacts" and type(parts[1]) is int and parts[2] == "flare_kind":
        index = parts[1]
        return left["final_contacts"][index].get("id") == right["final_contacts"][index].get("id") == MOBILE_ID
    return False


def _validate_schema2_provenance(name, capture, side, report):
    """Validate each record internally, without equating identities across builds."""
    runtime = capture.get("runtime_provenance")
    if not isinstance(runtime, dict):
        _error(report, "schema2_runtime_provenance", side=side, file=name,
               expected="object containing observed HUD methods and material uniforms")
    else:
        methods = runtime.get("hud_methods")
        if not isinstance(methods, dict) or any(type(methods.get(method)) is not bool for method in HUD_METHODS):
            _error(report, "schema2_hud_methods", side=side, file=name,
                   expected={method: "boolean" for method in sorted(HUD_METHODS)}, actual=methods)
        for field in ("hud_script_resource_path", "identity_limit"):
            value = runtime.get(field)
            if not isinstance(value, str) or (field == "identity_limit" and not value.strip()):
                _error(report, "schema2_runtime_provenance_field", side=side, file=name,
                       path=_path(("runtime_provenance", field)), expected="string", actual=value)
        contacts = capture.get("final_contacts")
        if not isinstance(contacts, list) or any(
            not isinstance(contact, dict) or not UNIFORM_FIELDS <= contact.keys()
            or not isinstance(contact.get("id"), str)
            or not _is_number(contact.get("mobile_phase"))
            or not _is_number(contact.get("flare_kind"))
            or type(contact.get("flare_visible")) is not bool
            for contact in contacts
        ):
            _error(report, "schema2_uniform_contact_fields", side=side, file=name)
        else:
            projected = [{field: contact[field] for field in sorted(UNIFORM_FIELDS)} for contact in contacts]
            observed = runtime.get("actual_ground_material_uniforms")
            if not isinstance(observed, list):
                _error(report, "schema2_observed_uniforms", side=side, file=name, expected="array", actual=observed)
            else:
                for parts, expected, actual in _differences(projected, observed):
                    _error(report, "schema2_uniform_projection_mismatch", side=side, file=name,
                           path=_path(("runtime_provenance", "actual_ground_material_uniforms") + parts),
                           expected=_report_value(expected), actual=_report_value(actual))

    for section in ("source_hashes", "filesystem_text_diagnostics"):
        records = capture.get(section)
        if not isinstance(records, dict):
            _error(report, "schema2_evidence_section", side=side, file=name,
                   path=_path((section,)), expected="object with the five recorded resources")
            continue
        if records.keys() != SOURCE_RESOURCES.keys():
            _error(report, "schema2_evidence_inventory", side=side, file=name,
                   path=_path((section,)), missing=sorted(SOURCE_RESOURCES.keys() - records.keys()),
                   extra=sorted(records.keys() - SOURCE_RESOURCES.keys()))
        for source, record in sorted(records.items()):
            if not isinstance(record, dict):
                _error(report, "schema2_evidence_record", side=side, file=name,
                       path=_path((section, source)), expected="object")
                continue
            expected_origin = RESOURCE_ORIGIN if section == "source_hashes" else FILESYSTEM_ORIGIN
            if record.get("origin") != expected_origin:
                _error(report, "schema2_evidence_origin", side=side, file=name,
                       path=_path((section, source, "origin")), expected=expected_origin, actual=record.get("origin"))
            digest = record.get("sha256")
            if not isinstance(digest, str) or (digest and not re.fullmatch(r"[0-9a-fA-F]{64}", digest)):
                _error(report, "schema2_evidence_sha256", side=side, file=name,
                       path=_path((section, source, "sha256")), expected="empty string or 64 hexadecimal digits", actual=digest)
            if section == "filesystem_text_diagnostics":
                if type(record.get("exists")) is not bool:
                    _error(report, "schema2_filesystem_exists", side=side, file=name,
                           path=_path((section, source, "exists")), expected="boolean", actual=record.get("exists"))
                if record.get("exists") is False and digest:
                    _error(report, "schema2_filesystem_hash_without_file", side=side, file=name, path=_path((section, source)))
                continue
            status = record.get("status")
            if status not in ("available", "unavailable_in_compiled_pack", "resource_unavailable"):
                _error(report, "schema2_evidence_status", side=side, file=name,
                       path=_path((section, source, "status")), actual=status)
            elif (status == "available" and not digest) or (status != "available" and digest != ""):
                _error(report, "schema2_evidence_status_hash", side=side, file=name,
                       path=_path((section, source)), status=status, sha256=digest,
                       expected="available has a hash; unavailable has an empty hash with no filesystem fallback")
            for field in ("kind", "resource_path", "api"):
                if not isinstance(record.get(field), str):
                    _error(report, "schema2_resource_field", side=side, file=name,
                           path=_path((section, source, field)), expected="string", actual=record.get(field))
            if status == "resource_unavailable":
                if record.get("kind") != "unknown" or record.get("api") != "" or record.get("resource_path") != "":
                    _error(report, "schema2_unavailable_resource_shape", side=side, file=name,
                           path=_path((section, source)), expected="kind=unknown, api='', resource_path=''")
            elif source in SOURCE_RESOURCES:
                expected_kind = SOURCE_RESOURCES[source]
                expected_api = "ResourceLoader.load().Shader.code" if expected_kind == "Shader" else "ResourceLoader.load().Script.get_source_code()"
                if record.get("kind") != expected_kind or record.get("api") != expected_api:
                    _error(report, "schema2_loaded_resource_api", side=side, file=name,
                           path=_path((section, source)), expected_kind=expected_kind, expected_api=expected_api,
                           actual_kind=record.get("kind"), actual_api=record.get("api"))


def _provenance(data, side, captures, report):
    counts = Counter()
    unavailable = {}
    embedded_files = set()
    for name, capture in sorted(captures.items()):
        hashes = capture.get("source_hashes")
        if not isinstance(hashes, dict):
            continue
        for source, record in sorted(hashes.items()):
            if not isinstance(record, dict):
                continue
            origin = str(record.get("origin", "missing origin"))
            counts[origin] += 1
            if origin == "embedded source file":
                embedded_files.add(name)
            if not record.get("sha256") or origin == "unavailable in compiled pack":
                unavailable.setdefault(source, []).append(name)
    build = data.get("build")
    kind = "sha256_label" if isinstance(build, str) and re.fullmatch(r"[0-9a-fA-F]{64}", build) else "source_candidate_marker_or_other_label"
    report["provenance"][side] = {
        "schema": data.get("schema"), "build": build, "build_label_kind": kind,
        "build_label_independently_verified": False,
        "source_hash_origin_counts": dict(sorted(counts.items())),
        "unavailable_source_hashes": unavailable,
        "captures_with_runtime_provenance": sum("runtime_provenance" in c for c in captures.values()),
    }
    if data.get("schema") == 1 and embedded_files:
        report["warnings"].append({
            "code": "schema1_filesystem_text_hash_is_not_bytecode_identity", "side": side,
            "affected_captures": len(embedded_files),
            "message": "Schema 1 'embedded source file' hashes came from FileAccess text. The legacy label is misleading: these hashes cannot establish the identity of the code/bytecode actually loaded from the pack.",
        })


def compare(before, after):
    """Return a serializable audit report; read manifests and original PNGs only."""
    paths = {"before": _manifest_location(before), "after": _manifest_location(after)}
    report = {
        "comparator_schema": 1, "pose_match": False, "errors": [], "warnings": [],
        "numeric_comparison": "Decimal exact numeric equality; no tolerance; booleans are not numbers",
        "decimal_values_in_report": "exact decimal strings",
        "expected_capture_count": 36, "expected_files": sorted(EXPECTED_FILES),
        "info_whitelist": {"capture_root_keys": sorted(CAPTURE_INFO), "top_root_keys": sorted(TOP_INFO)},
        "inputs": {}, "provenance": {}, "metadata_info_differences": [],
        "pairs": [], "limitations": LIMITATIONS,
    }
    data = {side: _load_manifest(path, side, report) for side, path in paths.items()}
    if any(manifest is None for manifest in data.values()):
        report["summary"] = {"paired_captures": 0, "hashed_original_pngs": 0, "errors": len(report["errors"])}
        return report
    indexed = {side: _capture_index(manifest, side, report) for side, manifest in data.items()}
    images = {side: _png_information(paths[side].parent, side, indexed[side], report) for side in paths}
    for side in paths:
        for name in sorted(indexed[side].keys() & EXPECTED_FILES):
            _validate_fixture(name, indexed[side][name], side, data[side], report)
            if data[side].get("schema") == 2:
                _validate_schema2_provenance(name, indexed[side][name], side, report)
        _provenance(data[side], side, indexed[side], report)
    top_left = {k: v for k, v in data["before"].items() if k != "captures"}
    top_right = {k: v for k, v in data["after"].items() if k != "captures"}
    for parts, left, right in _differences(top_left, top_right):
        difference = {"path": _path(parts), "before": _report_value(left), "after": _report_value(right)}
        if parts[0] in TOP_INFO:
            if _is_number(left) and _is_number(right):
                difference["delta"] = right - left
            report["metadata_info_differences"].append(difference)
        else:
            _error(report, "metadata_scenario_difference", **difference)
    for name in sorted(indexed["before"].keys() & indexed["after"].keys() & EXPECTED_FILES):
        left, right = indexed["before"][name], indexed["after"][name]
        pair = {"file": name, "pose_match": True, "expected_flare_differences": [],
                "info_differences": [], "images": {side: images[side].get(name) for side in paths}}
        for parts, old, new in _differences(left, right):
            difference = {"path": _path(parts), "before": _report_value(old), "after": _report_value(new)}
            if parts[0] in CAPTURE_INFO:
                if _is_number(old) and _is_number(new):
                    difference["delta"] = new - old
                pair["info_differences"].append(difference)
            elif _flare_exception(name, parts, old, new, left, right):
                pair["expected_flare_differences"].append(difference)
            else:
                _error(report, "scenario_difference", file=name, **difference)
        pair["pose_match"] = not any(error.get("file") == name for error in report["errors"])
        report["pairs"].append(pair)
    report["pose_match"] = not report["errors"]
    report["summary"] = {
        "paired_captures": len(report["pairs"]),
        "hashed_original_pngs": sum(len(entries) for entries in images.values()),
        "expected_flare_differences": sum(len(p["expected_flare_differences"]) for p in report["pairs"]),
        "capture_info_differences": sum(len(p["info_differences"]) for p in report["pairs"]),
        "metadata_info_differences": len(report["metadata_info_differences"]),
        "errors": len(report["errors"]),
    }
    return report


def _json_default(value):
    if isinstance(value, Decimal):
        return str(value)
    raise TypeError(f"Cannot encode {type(value).__name__}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True, help="Before captures.json or capture directory")
    parser.add_argument("--after", required=True, help="After captures.json or capture directory")
    parser.add_argument("--output", required=True, help="Audit JSON outside both capture directories")
    args = parser.parse_args(argv)
    output = Path(args.output).resolve()
    for argument in (args.before, args.after):
        directory = _manifest_location(argument).parent
        if output == directory or output.is_relative_to(directory):
            parser.error("--output must be outside both capture directories; originals are read-only")
    report = compare(args.before, args.after)
    try:
        # Only the explicitly requested report path is written. No mkdir or image writes.
        output.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False,
                                     default=_json_default) + "\n", encoding="utf-8")
    except (OSError, ValueError, TypeError) as exc:
        print(f"Cannot write audit report: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({"pose_match": report["pose_match"], "summary": report["summary"], "output": str(output)}))
    return 0 if report["pose_match"] else 1


if __name__ == "__main__":
    sys.exit(main())
