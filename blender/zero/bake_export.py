"""Bake the authored Zero materials into portable UV/PBR maps, then GLB.
Run with zero-studio.blend loaded. Never overwrite that source studio file.
"""
import bpy, json, math
from pathlib import Path
ROOT=Path('C:/ChatGPT/1942');OUT=ROOT/'blender/zero';TEX=ROOT/'art/enemies/zero/textures/v01'
scene=bpy.context.scene;air=bpy.data.collections['ZERO | airframe']
bpy.ops.object.select_all(action='DESELECT')
for ob in list(air.objects):
    if ob.type not in ['MESH','CURVE']:continue
    is_prop=ob.parent is not None and ob.parent.name=='PROPELLER'
    ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.convert(target='MESH')
    ob=bpy.context.object
    if ob.data.uv_layers:
        ob.data.uv_layers.active.name='UV_Source'
    else:
        ob.data.uv_layers.new(name='UV_Source')
    if is_prop:
        group=ob.vertex_groups.new(name='PropellerMotion');group.add(list(range(len(ob.data.vertices))),1,'REPLACE')
    matrix=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=matrix
    ob.select_set(False)
for ob in air.objects:
    if ob.type=='MESH':ob.select_set(True);bpy.context.view_layer.objects.active=ob
bpy.ops.object.join();ob=bpy.context.object;ob.name='Zero airframe + propeller | baked UV'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# Preserve authored UVs for source textures; create a separate bake destination.
source_uv=ob.data.uv_layers.active.name
for mat in ob.data.materials:
    for node in list(mat.node_tree.nodes):
        if node.type=='TEX_IMAGE':
            uv=mat.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map=source_uv
            mat.node_tree.links.new(uv.outputs['UV'],node.inputs['Vector'])
uv=ob.data.uv_layers.new(name='UV_Zero_PBR');ob.data.uv_layers.active=uv
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.012)
bpy.ops.object.mode_set(mode='OBJECT')
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.render.bake.margin=12
scene.render.bake.use_selected_to_active=False
scene.render.bake.use_pass_direct=False;scene.render.bake.use_pass_indirect=False;scene.render.bake.use_pass_color=True
images={}
for kind,bake_type in [('basecolor','EMIT'),('roughness','ROUGHNESS'),('normal','NORMAL'),('metallic','EMIT')]:
    image=bpy.data.images.new('zero_'+kind,width=2048,height=2048,alpha=False)
    if kind!='basecolor':image.colorspace_settings.name='Non-Color'
    for mat in ob.data.materials:
        nodes=mat.node_tree.nodes
        for node in nodes:node.select=False
        node=nodes.new('ShaderNodeTexImage');node.image=image;node.select=True;nodes.active=node
    restore=[]
    if kind in ['basecolor','metallic']:
        for mat in ob.data.materials:
            nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=nodes.get('Principled BSDF');out=nodes.get('Material Output')
            source=p.inputs['Base Color' if kind=='basecolor' else 'Metallic']
            value=source.default_value
            emission=nodes.new('ShaderNodeEmission');emission.inputs[0].default_value=value if kind=='basecolor' else (value,value,value,1)
            if source.is_linked:links.new(source.links[0].from_socket,emission.inputs[0])
            links.new(emission.outputs[0],out.inputs['Surface']);restore.append((mat,p,out,emission))
    bpy.ops.object.bake(type=bake_type)
    for mat,p,out,emission in restore:
        mat.node_tree.links.new(p.outputs[0],out.inputs['Surface']);mat.node_tree.nodes.remove(emission)
    image.filepath_raw=str(TEX/('zero_'+kind+'.png'));image.file_format='PNG';image.save();images[kind]=image
mat=bpy.data.materials.new('Zero | portable PBR');mat.use_nodes=True
n=mat.node_tree.nodes;l=mat.node_tree.links;p=n.get('Principled BSDF')
for kind,target in [('basecolor','Base Color'),('roughness','Roughness'),('metallic','Metallic')]:
    tex=n.new('ShaderNodeTexImage');tex.image=images[kind];l.new(tex.outputs['Color'],p.inputs[target])
tex=n.new('ShaderNodeTexImage');tex.image=images['normal'];normal=n.new('ShaderNodeNormalMap')
l.new(tex.outputs['Color'],normal.inputs['Color']);l.new(normal.outputs['Normal'],p.inputs['Normal'])
ob.data.materials.clear();ob.data.materials.append(mat)
for poly in ob.data.polygons:poly.material_index=0
# Keep only the UV layout that was baked, and split the propeller for animation.
for layer in list(ob.data.uv_layers):
    if layer.name!='UV_Zero_PBR':ob.data.uv_layers.remove(layer)
group=ob.vertex_groups.get('PropellerMotion')
if group:
    bpy.context.tool_settings.mesh_select_mode=(True,False,False)
    for polygon in ob.data.polygons:polygon.select=False
    for edge in ob.data.edges:edge.select=False
    for vert in ob.data.vertices:vert.select=any(g.group==group.index for g in vert.groups)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.separate(type='SELECTED');bpy.ops.object.mode_set(mode='OBJECT')
body=ob;body.name='Zero_Airframe'
for part in list(air.objects):
    if part.type=='MESH' and part!=body:
        part.name='Zero_Propeller'
        bpy.ops.object.select_all(action='DESELECT');part.select_set(True)
        bpy.context.view_layer.objects.active=part
        scene.cursor.location=(0,-3.69,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
bpy.ops.object.select_all(action='DESELECT')
meshes=[o for o in air.objects if o.type=='MESH']
for part in meshes:part.select_set(True);part.data.calc_loop_triangles()
bpy.ops.export_scene.gltf(filepath=str(OUT/'zero.glb'),export_format='GLB',use_selection=True,
    export_apply=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True)
for image in images.values():image.pack()
scene.camera=bpy.data.objects['03 TROIS QUARTS']
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'zero-pbr.blend'))
report={'meshes':len(meshes),'triangles':sum(len(o.data.loop_triangles) for o in meshes),
        'maps':{k:str(TEX/('zero_'+k+'.png')) for k in images},'map_resolution':2048,
        'normal_note':'Tangent-space bake of material microrelief, not a high-poly sculpt bake',
        'forward_in_gltf':'+Z','propeller_separate':any(o.name=='Zero_Propeller' for o in meshes)}
(OUT/'export-report.json').write_text(json.dumps(report,indent=2))
print('ZERO PBR EXPORT COMPLETE',report)
