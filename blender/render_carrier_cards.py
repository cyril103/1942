import bpy, math
from mathutils import Vector
from pathlib import Path
root=Path('C:/ChatGPT/1942')
bpy.ops.wm.open_mainfile(filepath=str(root/'blender/avion-joueur-studio.blend'))
s=bpy.context.scene
s.render.engine='CYCLES'
s.cycles.samples=24
s.cycles.use_denoising=True
s.render.resolution_x=900
s.render.resolution_y=520
s.render.resolution_percentage=100
s.render.film_transparent=True
s.render.image_settings.file_format='PNG'
s.render.image_settings.color_mode='RGBA'
cam=s.camera
cam.data.type='ORTHO'
cam.data.ortho_scale=12.7
for name,loc in [('vanguard',(10,-14,10))]:
 cam.location=loc
 cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler()
 s.render.filepath=str(root/('game/assets/campaign/carrier-ui/'+name+'.png'))
 bpy.ops.render.render(write_still=True)
