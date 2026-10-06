"""Bake four original volumetric cloud impostors; Blender 4.5, no downloads."""
import bpy, math, random
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'blender/clouds'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 96
scene.cycles.use_denoising = True
scene.cycles.volume_bounces = 2
scene.cycles.volume_step_rate = 1.25
scene.render.resolution_x = scene.render.resolution_y = 1536
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '8'
scene.view_settings.view_transform = 'AgX'
scene.view_settings.exposure = 1.0
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'CUDA'
    prefs.get_devices()
    gpu = False
    for device in prefs.devices:
        device.use = device.type == 'CUDA'
        gpu |= device.use
    if gpu: scene.cycles.device = 'GPU'
except Exception as exc:
    print('CPU fallback:', exc)

world = bpy.data.worlds.new('Cool sky fill')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (.64,.76,1,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = .25
scene.world = world

rng = random.Random(194207)
centers = [(-5,5),(5,5),(-5,-5),(5,-5)]
for variant,(cx,cy) in enumerate(centers):
    # One continuous density field per cloud avoids intersecting volume bounds.
    mat = bpy.data.materials.new(f'Cumulus density field {variant}')
    mat.use_nodes = True
    nodes,links = mat.node_tree.nodes,mat.node_tree.links
    nodes.clear()
    def node(kind, **props):
        n = nodes.new(kind)
        for k,v in props.items(): setattr(n,k,v)
        return n
    tex = node('ShaderNodeTexCoord')
    field = None
    for i in range(18):
        t = i/17
        a = t*math.tau*2.4+variant*.9
        radius = .50*math.sqrt(t)
        x = math.cos(a)*radius*(1.1 if variant==1 else 1)
        y = math.sin(a)*radius*(.60 if variant==1 else 1)
        if variant==2: y += .12*math.sin(x*6)
        if variant==3: x += .25*y
        z = .18*(1-t)+rng.uniform(-.13,.13)
        dist = node('ShaderNodeVectorMath',operation='DISTANCE')
        links.new(tex.outputs['Object'],dist.inputs[0])
        dist.inputs[1].default_value = (x,y,z)
        puff = node('ShaderNodeMath',operation='SUBTRACT')
        puff.inputs[0].default_value = rng.uniform(.23,.34)*(1-.2*t)
        links.new(dist.outputs['Value'],puff.inputs[1])
        if field is None: field = puff.outputs[0]
        else:
            union = node('ShaderNodeMath',operation='SMOOTH_MAX')
            union.inputs[2].default_value = .055
            links.new(field,union.inputs[0]); links.new(puff.outputs[0],union.inputs[1])
            field = union.outputs[0]
    noise = node('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 13
    noise.inputs['Detail'].default_value = 4
    noise.inputs['Roughness'].default_value = .7
    links.new(tex.outputs['Object'],noise.inputs['Vector'])
    erode = node('ShaderNodeMath',operation='MULTIPLY_ADD')
    erode.inputs[1].default_value = .12
    erode.inputs[2].default_value = -.07
    links.new(noise.outputs['Fac'],erode.inputs[0])
    add = node('ShaderNodeMath',operation='ADD')
    links.new(field,add.inputs[0]); links.new(erode.outputs[0],add.inputs[1])
    fade = node('ShaderNodeMapRange',interpolation_type='SMOOTHSTEP')
    fade.inputs['From Min'].default_value = -.025
    fade.inputs['From Max'].default_value = .085
    fade.inputs['To Min'].default_value = 0
    fade.inputs['To Max'].default_value = 1.6
    links.new(add.outputs[0],fade.inputs['Value'])
    volume = node('ShaderNodeVolumePrincipled')
    volume.inputs['Color'].default_value = (.985,.99,1,1)
    volume.inputs['Anisotropy'].default_value = .15
    links.new(fade.outputs[0],volume.inputs['Density'])
    out = node('ShaderNodeOutputMaterial')
    links.new(volume.outputs['Volume'],out.inputs['Volume'])
    bpy.ops.mesh.primitive_cube_add(size=2, location=(cx,cy,1.8))
    ob = bpy.context.object
    ob.name = f'Cumulus_{variant}_continuous_volume'
    ob.scale = (4.7,4.7,3.2)
    ob.data.materials.append(mat)

bpy.ops.object.light_add(type='SUN',location=(-8,10,14))
sun = bpy.context.object
sun.rotation_euler = (Vector((0,0,0))-sun.location).to_track_quat('-Z','Y').to_euler()
sun.data.energy = 4.0
sun.data.angle = .2
bpy.ops.object.camera_add(location=(0,0,35))
camera = bpy.context.object
camera.rotation_euler = (0,0,0)
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 20
scene.camera = camera
scene.render.filepath = str(OUT/'cumulus-volume-bake.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blender/clouds/clouds-studio.blend'))
bpy.ops.render.render(write_still=True)
print('CLOUD ATLAS COMPLETE:', scene.render.filepath)
