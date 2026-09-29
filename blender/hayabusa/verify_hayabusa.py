import bpy, json, struct
from pathlib import Path
ROOT=Path('C:/ChatGPT/1942');OUT=ROOT/'blender/hayabusa'
assert len([o for o in bpy.data.objects if o.type=='CAMERA'])==3
assert bpy.context.scene.world.node_tree.nodes.get('Environment Texture').image.packed_file
for name in ['01-dessus','02-dessous','03-trois-quarts']:
    im=bpy.data.images.load(str(ROOT/'renders/hayabusa'/(name+'.png')),check_existing=False)
    assert tuple(im.size)==(2200,2200)
data=(OUT/'hayabusa.glb').read_bytes();magic,version,total=struct.unpack_from('<III',data)
assert magic==0x46546C67 and version==2 and total==len(data)
size,kind=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+size])
assert len(doc['meshes'])==2
assert all('bufferView' in im for im in doc['images'])
assert len(doc['images'])>=3
for ob in list(bpy.data.collections['HAYABUSA | airframe'].objects):bpy.data.objects.remove(ob,do_unlink=True)
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(OUT/'hayabusa.glb'))
imported=[ob for ob in bpy.data.objects if ob not in before and ob.type=='MESH']
assert len(imported)==2
for ob in imported:
    assert len(ob.data.vertices)>0
    assert ob.data.uv_layers
scene=bpy.context.scene;scene.camera=bpy.data.objects['03 TROIS QUARTS']
scene.cycles.samples=24;scene.render.resolution_x=scene.render.resolution_y=900
scene.render.filepath=str(ROOT/'renders/hayabusa/glb-verification.png');bpy.ops.render.render(write_still=True)
report={'source_blend_reopened':True,'studio_cameras':3,'hdr_packed':True,'final_renders_2200':3,
        'glb_reimported_meshes':2,'glb_embedded_textures':len(doc['images']),
        'materials':len(doc['materials']),'glb_bytes':len(data),'glb_render':'../../renders/hayabusa/glb-verification.png'}
(OUT/'verification.json').write_text(json.dumps(report,indent=2));print('HAYABUSA VERIFIED',report)
