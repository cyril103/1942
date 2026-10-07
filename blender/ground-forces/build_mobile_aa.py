"""Compact wheeled AA, existing field atlas; two production meshes.

Prepared from blender/ground-forces/build_ground_forces.py's UV/material contract.
Do not run Blender during a benchmark. No render is invoked by this script.
Future authorized command: blender --background --python <this file>.
Outputs only battery_mobile.glb plus its source/report. No existing asset or
gameplay collision is overwritten. No rendering is invoked.
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path("C:/ChatGPT/1942")
OUT = ROOT / "game/assets/ground-forces"
SOURCE = ROOT / "blender/ground-forces"
ATLAS = ROOT / "game/assets/ground-forces/field-material-atlas.png"
MAX_TRIANGLES = 2200
FOOTPRINT = (2.8, 2.8)
OLIVE, CONCRETE, ROOF, CANVAS, STEEL, WOOD = range(6)
METAL = [.30, .0, .55, .0, .72, .0]

OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
atlas = bpy.data.images.load(str(ATLAS))
atlas.pack()
material = bpy.data.materials.new("Mobile AA | existing FieldFinish atlas")
material.use_nodes = True
nodes, links = material.node_tree.nodes, material.node_tree.links
bsdf = nodes.get("Principled BSDF")
texture = nodes.new("ShaderNodeTexImage")
texture.image = atlas
color = nodes.new("ShaderNodeVertexColor")
color.layer_name = "FieldFinish"
multiply = nodes.new("ShaderNodeMixRGB")
multiply.blend_type = "MULTIPLY"
multiply.inputs[0].default_value = 1
links.new(texture.outputs["Color"], multiply.inputs[1])
links.new(color.outputs["Color"], multiply.inputs[2])
links.new(multiply.outputs["Color"], bsdf.inputs["Base Color"])
links.new(color.outputs["Alpha"], bsdf.inputs["Metallic"])
bsdf.inputs["Roughness"].default_value = .65
parts = {"Hull": [], "Turret": []}
assembly = "Hull"


def finish(obj, cell=OLIVE, tint=(1, 1, 1), bevel=0, smooth=False):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("Single segment machined edge", "BEVEL")
        modifier.width, modifier.segments = bevel, 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    mesh = obj.data
    uv = mesh.uv_layers.active or mesh.uv_layers.new(name="FieldUV")
    uv.name = "FieldUV"
    bounds = [max(abs(v.co[i]) for v in mesh.vertices) or 1 for i in range(3)]
    for polygon in mesh.polygons:
        axis = max(range(3), key=lambda i: abs(polygon.normal[i]))
        axes = [i for i in range(3) if i != axis]
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            u = .5 + vertex[axes[0]] / (2 * bounds[axes[0]])
            v = .5 + vertex[axes[1]] / (2 * bounds[axes[1]])
            uv.data[loop_index].uv = ((cell % 3 + .025 + .95 * u) / 3,
                                       1 - (cell // 3 + .025 + .95 * (1 - v)) / 2)
        polygon.use_smooth = smooth
    colors = mesh.color_attributes.new(name="FieldFinish", type="FLOAT_COLOR", domain="CORNER")
    for item in colors.data:
        item.color = (*tint, METAL[cell])
    mesh.materials.clear()
    mesh.materials.append(material)
    parts[assembly].append(obj)
    return obj


def box(name, at, dims, cell=OLIVE, tint=(1, 1, 1), bevel=0, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at, rotation=rotation)
    obj = bpy.context.object
    obj.name, obj.scale = name, dims
    return finish(obj, cell, tint, bevel)


def cylinder(name, at, radius, length, cell=STEEL, tint=(1, 1, 1), vertices=12, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=length, location=at, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, cell, tint, smooth=True)


def rod(name, start, end, radius, cell=STEEL, tint=(1, 1, 1), vertices=12):
    start, end = Vector(start), Vector(end)
    direction = end - start
    obj = cylinder(name, (start + end) * .5, radius, direction.length, cell, tint, vertices)
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return obj


# Blender -Y maps to the vehicle's Godot +Z nose after Y-up export.
# Six independent wheel silhouettes remain readable from the raid camera.
box("Open armored chassis", (0, .06, .39), (1.34, 2.02, .23), bevel=.015)
box("Rear AA deck", (0, .34, .60), (1.42, 1.26, .12))
box("Engine hood", (0, -.77, .62), (1.16, .44, .36), bevel=.012)
box("Compact cab body", (0, -.39, .69), (1.20, .47, .53), bevel=.012)
box("Flat cab roof", (0, -.39, .97), (1.28, .56, .065), bevel=.012)
box("Split windshield left", (-.29, -.636, .84), (.49, .018, .18), STEEL, (.13, .38, .44))
box("Split windshield right", (.29, -.636, .84), (.49, .018, .18), STEEL, (.13, .38, .44))
box("Windshield mullion", (0, -.65, .84), (.027, .025, .20))
for side in [-1, 1]:
    box("Side cab glass", (side * .609, -.39, .83), (.018, .31, .17), STEEL, (.13, .38, .44))
    box("Driver step", (side * .69, -.40, .39), (.23, .43, .055), STEEL)
    box("Rear equipment locker", (side * .48, .73, .77), (.32, .37, .23), OLIVE, (.83, .91, .78))
    for axle_y in [-.74, .20, .79]:
        cylinder("Black rubber road tire", (side * .73, axle_y, .255), .255, .23, STEEL, (.15, .17, .16), vertices=12, rotation=(0, math.pi / 2, 0))
        cylinder("Olive wheel hub", (side * .858, axle_y, .255), .105, .026, OLIVE, vertices=8, rotation=(0, math.pi / 2, 0))
        box("Wheel fender", (side * .67, axle_y, .535), (.40, .57, .065))
for axle_y in [-.74, .20, .79]:
    rod("Steel axle", (-.71, axle_y, .255), (.71, axle_y, .255), .055, vertices=8)
for bumper_y in [-1.04, 1.08]:
    box("Impact bumper", (0, bumper_y, .40), (1.47, .09, .10), STEEL)
for x in [-.48, -.32, -.16, 0, .16, .32, .48]:
    box("Radiator grille slat", (x, -1.002, .64), (.042, .022, .20), STEEL, (.34, .41, .35))
for x in [-.49, .49]:
    cylinder("Warm lamp", (x, -1.022, .79), .065, .025, CONCRETE, (1.12, 1.04, .68), vertices=8, rotation=(math.pi / 2, 0, 0))

# The only moving mesh has a real traverse pivot above the rear deck.
assembly = "Turret"
pivot = (0, .18, .77)
cylinder("Traverse bearing", pivot, .38, .15, STEEL, vertices=16)
cylinder("Low AA pedestal", (0, .18, .85), .235, .22, OLIVE)
for side in [-1, 1]:
    box("Trunnion cradle", (side * .28, .14, 1.00), (.13, .38, .34), bevel=.012)
    box("Folded armored shield", (side * .37, -.10, 1.03), (.32, .06, .30), rotation=(.18, 0, side * .15))
    box("Ammunition feed box", (side * .39, .35, .99), (.26, .32, .22), STEEL)
    box("Twin cannon breech", (side * .14, .06, 1.08), (.15, .44, .18), bevel=.012)
    rod("Recoil sleeve", (side * .14, -.11, 1.06), (side * .14, -.55, 1.23), .070, OLIVE)
    rod("Long cannon barrel", (side * .14, -.49, 1.21), (side * .14, -1.15, 1.43), .033, STEEL)
    rod("Muzzle collar", (side * .14, -1.11, 1.415), (side * .14, -1.19, 1.447), .052, STEEL)
    rod("Dark bore cap", (side * .14, -1.189, 1.447), (side * .14, -1.193, 1.448), .029, STEEL, (.12, .13, .12))
box("Gunner seat", (0, .61, .92), (.28, .24, .055), WOOD, (.50, .47, .40))
rod("Optical sight", (0, .12, 1.19), (0, -.26, 1.30), .018, vertices=8)


def joined(objects, name, origin):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    scene.cursor.location = origin
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    while len(obj.data.materials) > 1:
        obj.data.materials.pop(index=1)
    obj.data.calc_loop_triangles()
    return obj


hull = joined(parts["Hull"], "Hull", (0, 0, 0))
turret = joined(parts["Turret"], "Turret", pivot)
model = bpy.data.objects.new("MobileBattery", None)
scene.collection.objects.link(model)
hull.parent = model
turret.parent = model
bpy.context.view_layer.update()
points = [obj.matrix_world @ vertex.co for obj in [hull, turret] for vertex in obj.data.vertices]
extents = [max(v[i] for v in points) - min(v[i] for v in points) for i in range(3)]
triangles = sum(len(obj.data.loop_triangles) for obj in [hull, turret])
assert triangles <= MAX_TRIANGLES, f"Mobile AA triangle budget exceeded: {triangles}"
assert max(abs(v.x) for v in points) <= 1.4 and max(abs(v.y) for v in points) <= 1.4, extents
# Full turret yaw must stay inside the unchanged 2.8 x 2.8 gameplay footprint.
assert max(math.hypot(v.x - pivot[0], v.y - pivot[1]) for v in [turret.matrix_world @ item.co for item in turret.data.vertices]) <= 1.4
bpy.ops.object.select_all(action="DESELECT")
for obj in [model, hull, turret]:
    obj.select_set(True)
bpy.context.view_layer.objects.active = model
bpy.ops.export_scene.gltf(filepath=str(OUT / "battery_mobile.glb"), export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=True, export_materials="NONE",
                          export_vertex_color="NAME", export_vertex_color_name="FieldFinish",
                          export_normals=True, export_texcoords=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "battery_mobile.blend"))
report = {"triangles": triangles, "meshes": 2, "surfaces": 2, "width_depth_height": extents,
          "footprint": FOOTPRINT, "turret_pivot_blender": pivot, "atlas": str(ATLAS),
          "forward_blender": "-Y", "forward_godot": "+Z", "runtime_variant": "battery",
          "rendered_or_imported_in_game": False}
(SOURCE / "battery-mobile-build-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("MOBILE_AA_BUILD_REPORT", json.dumps(report))
