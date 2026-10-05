"""Render the final baked, portable model using the packed HDR studio."""
import bpy
from pathlib import Path
root=Path('C:/ChatGPT/1942')
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=96
scene.cycles.use_denoising=True
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type='CUDA';prefs.get_devices()
    for device in prefs.devices: device.use=device.type=='CUDA'
    if any(device.use for device in prefs.devices): scene.cycles.device='GPU'
except Exception as error:
    print('Cycles CPU fallback',error)
scene.render.resolution_x=scene.render.resolution_y=2200
scene.render.resolution_percentage=100
for camera,name in [('01 DESSUS','01-dessus'),('02 DESSOUS','02-dessous'),('03 TROIS QUARTS','03-trois-quarts')]:
    scene.camera=bpy.data.objects[camera]
    scene.render.filepath=str(root/'renders/bomber'/f'{name}.png')
    bpy.ops.render.render(write_still=True)
scene.camera=bpy.data.objects['03 TROIS QUARTS']
bpy.ops.wm.save_as_mainfile(filepath=str(root/'blender/bomber/bomber-pbr.blend'))
