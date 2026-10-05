"""Re-import the GLB and verify portable textures, mesh budget and prop pivots."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector
root=Path('C:/ChatGPT/1942')
studio_images=[i for i in bpy.data.images if i.source=='FILE']
assert any('studio_small' in i.name and i.packed_file for i in studio_images),'Missing packed HDR'
assert any('reference' in i.name and i.packed_file for i in studio_images),'Missing packed reference'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'blender/bomber/bomber.glb'))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
assert len(meshes)==3,[o.name for o in meshes]
triangles=0
for ob in meshes:
    ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
    assert ob.data.uv_layers,ob.name
    assert all(math.isfinite(v) for vert in ob.data.vertices for v in vert.co)
    assert all(-.001<=v<=1.001 for uv in ob.data.uv_layers.active.data for v in uv.uv)
    assert all(len(p.vertices)==3 for p in ob.data.polygons),'GLB not triangulated'
for name,x in [('Bomber_Propeller_L',-2.62),('Bomber_Propeller_R',2.62)]:
    ob=bpy.data.objects[name]
    assert (ob.matrix_world.translation-Vector((x,-5.30,-.04))).length<.002,(name,ob.matrix_world.translation)
assert triangles<15000,triangles
textures=[i for i in bpy.data.images if i.type=='IMAGE']
assert len(textures)>=3,'Expected embedded basecolor, packed MR, normal'
assert all(tuple(i.size)==(2048,2048) for i in textures)
report={'status':'PASS','triangles':triangles,'meshes':[o.name for o in meshes],'embedded_textures':len(textures),'texture_resolution':2048,'independent_propeller_pivots':True,'studio_hdr_and_reference_packed':True}
(root/'blender/bomber/verification.json').write_text(json.dumps(report,indent=2))
print('BOMBER VERIFIED',report)
