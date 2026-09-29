"""Export the existing textured aircraft; do not change the studio .blend."""
import bpy, numpy as np, os, json
ROOT='C:/ChatGPT/1942'
DEST=ROOT+'/game/assets'
os.makedirs(DEST,exist_ok=True)
air=bpy.data.collections['AIRCRAFT | Player 01']
keep=set(air.objects)
for ob in list(bpy.data.objects):
    if ob not in keep:bpy.data.objects.remove(ob,do_unlink=True)

# Resolve Blender-only hue and alpha shader nodes into portable glTF textures.
# The original source images are preserved. These are derived engine textures.
def engine_texture(src, name, alpha=False):
    w,h=src.size
    values=np.empty(w*h*4,dtype=np.float32);src.pixels.foreach_get(values)
    values=values.reshape((-1,4));rgb=values[:,:3].copy()
    if alpha:values[:,3]=(rgb[:,2]>rgb[:,0]*.85).astype(np.float32)
    maximum=rgb.max(axis=1,keepdims=True)
    values[:,:3]=np.clip((maximum+(rgb-maximum)*1.10)*.68,0,1)
    out=bpy.data.images.new(name,width=w,height=h,alpha=True)
    out.pixels.foreach_set(values.ravel());out.update()
    out.filepath_raw=DEST+'/'+name+'.png';out.file_format='PNG';out.save()
    return out

atlas=bpy.data.images['aircraft-atlas-color-source.png']
trim=bpy.data.images['aircraft-paint-trim-color-source.png']
images={False:engine_texture(atlas,'aircraft_atlas'),True:engine_texture(atlas,'aircraft_insignia',True)}
paint=engine_texture(trim,'aircraft_paint')
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    old=next((n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'),None)
    if not old:continue
    is_decal='insignia' in mat.name.lower()
    image=images[is_decal] if old.image==atlas else paint
    p=mat.node_tree.nodes.get('Principled BSDF')
    for n in list(mat.node_tree.nodes):
        if n.type not in ['BSDF_PRINCIPLED','OUTPUT_MATERIAL']:mat.node_tree.nodes.remove(n)
    n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=image
    mat.node_tree.links.new(n.outputs['Color'],p.inputs['Base Color'])
    if is_decal:
        mat.node_tree.links.new(n.outputs['Alpha'],p.inputs['Alpha'])
        mat.surface_render_method='DITHERED'
        mat.use_backface_culling=False

# Convert presentation curves and evaluate small bevels; merge static geometry
# by material to keep the engine draw-call count small.
bpy.ops.object.select_all(action='DESELECT')
for ob in list(air.objects):
    if ob.type in ['MESH','CURVE']:ob.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in air.objects if o.type=='MESH')
bpy.ops.object.convert(target='MESH')
groups={}
for ob in list(air.objects):
    if ob.type!='MESH':continue
    # Clear parenting while preserving the posed, stationary propeller.
    matrix=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=matrix
    key=ob.data.materials[0].name if ob.data.materials else 'Unpainted'
    groups.setdefault(key,[]).append(ob)
for name,objects in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    if len(objects)>1:bpy.ops.object.join()
    ob=bpy.context.object;ob.name=name.replace(' | ','_')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    ob.data.calc_loop_triangles()
bpy.ops.object.select_all(action='DESELECT')
for ob in air.objects:
    if ob.type=='MESH':ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=DEST+'/aircraft.glb',export_format='GLB',use_selection=True,
    export_apply=True,export_animations=False,export_cameras=False,export_lights=False,
    export_materials='EXPORT',export_yup=True)
report={'meshes':len(groups),'triangles':sum(len(o.data.loop_triangles) for o in air.objects if o.type=='MESH'),
        'source_blend':'../blender/avion-joueur-studio.blend','forward_in_gltf':'+Z',
        'textures':'Derived from original atlas and paint trim, embedded in GLB'}
with open(DEST+'/export-report.json','w') as f:json.dump(report,f,indent=2)
print('GODOT EXPORT COMPLETE',report)
