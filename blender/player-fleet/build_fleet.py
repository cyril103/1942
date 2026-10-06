"""Author two recognizable low-poly aircraft from the saved concept boards.
Units normalized to the Vanguard's 9.5 unit span; -Y nose, Z up.
Generated trim atlas UVs, separate propellers, packed editable Blender sources.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
from math import sin, cos, pi
ROOT=Path('C:/ChatGPT/1942')
DEST=ROOT/'game/assets/player-fleet'
OUT=ROOT/'renders/player-fleet'

def build(kind):
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
 for mat in list(bpy.data.materials): bpy.data.materials.remove(mat)
 s=bpy.context.scene
 aircraft=[]
 atlas=bpy.data.images.load(str(ROOT/f'art/player-fleet/{kind}-albedo.png'),check_existing=True)
 def material(name,color,rough=.4,metal=0,tex=False):
  m=bpy.data.materials.new(name);m.use_nodes=True
  p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
  p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
  if tex:
   n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=atlas
   m.node_tree.links.new(n.outputs['Color'],p.inputs['Base Color'])
  return m
 paint=material('Aircraft_skin',(.4,.4,.4),.43,.65 if kind=='p38' else .20,True)
 dark=material('Recesses',(.018,.022,.027),.65)
 steel=material('Machined_metal',(.24,.28,.32),.28,.8)
 glass=material('Canopy_glass',(.022,.115,.17),.17,.45)
 glass.node_tree.nodes.get('Principled BSDF').inputs['Coat Weight'].default_value=.7
 white=material('Insignia_white',(.88,.89,.83),.48)
 navy=material('Insignia_navy',(.012,.025,.065),.48)
 yellow=material('Safety_yellow',(.94,.63,.065),.36,.1)
 frame=material('Canopy_frame',(.23,.25,.16) if kind=='p38' else (.033,.075,.13),.38,.3)
 def uvband(b,u,v):return (.035+.93*max(0,min(1,u)),1-(b+.06+.88*max(0,min(1,v)))/4)
 def mesh(name,v,f,mat=paint,band=0,uv=None,smooth=False):
  me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update()
  ob=bpy.data.objects.new(name,me);s.collection.objects.link(ob);me.materials.append(mat);aircraft.append(ob)
  layer=me.uv_layers.new(name='Authored_trim_UV')
  for poly in me.polygons:
   poly.use_smooth=smooth
   for li in poly.loop_indices:
    co=me.vertices[me.loops[li].vertex_index].co
    layer.data[li].uv=uv(co,poly) if uv else uvband(band,(co.x+4.75)/9.5,(co.y+4)/8)
  return ob
 def tube(name,points,r,mat):
  # Explicit octagonal tubes export without curve conversion ambiguity.
  v=[]
  for j,p in enumerate(points):
   tangent=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(0,j-1)])
   tangent.normalize();ref=Vector((0,0,1)) if abs(tangent.z)<.9 else Vector((1,0,0))
   a=tangent.cross(ref).normalized();b=tangent.cross(a).normalized()
   for k in range(6):v.append(Vector(p)+r*(cos(k*pi/3)*a+sin(k*pi/3)*b))
  return mesh(name,v,[(j*6+k,j*6+(k+1)%6,(j+1)*6+(k+1)%6,(j+1)*6+k) for j in range(len(points)-1) for k in range(6)],mat)
 def body(name,rings,x=0):
  v=[];n=20
  for y,rx,rz,z in rings:
   for j in range(n):a=j*2*pi/n;v.append((x+rx*sin(a),y,z+rz*cos(a)))
  faces=[(k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j) for k in range(len(rings)-1) for j in range(n)]
  faces += [tuple(reversed(range(n))),tuple((len(rings)-1)*n+j for j in range(n))]
  def uv(co,p):
   z=co.z
   band=1 if p.normal.z<-.3 else 0
   return uvband(band,(co.y-rings[0][0])/(rings[-1][0]-rings[0][0]),(math.atan2(co.x-x,z)/(2*pi))%1)
  ob=mesh(name,v,faces,uv=uv,smooth=True)
  for y,rx,rz,z in rings[2:-2:2]:
   tube('Panel_joint',[(x+(rx+.003)*sin(j*2*pi/n),y,z+(rz+.003)*cos(j*2*pi/n)) for j in range(n+1)],.004,dark)
  return ob
 def solid(name,outline,axis='Z',thick=.045,mat=paint):
  v=[]
  for side in [-1,1]:
   for co in outline:
    v.append((co[0],co[1],co[2]+side*thick) if axis=='Z' else (co[0],co[1]+side*thick,co[2]) if axis=='Y' else (co[0]+side*thick,co[1],co[2]))
  n=len(outline);f=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
  return mesh(name,v,f,mat,uv=lambda c,p:uvband(1 if axis=='Z' and p.index==0 else 0,(c.y+4)/8 if axis=='X' else (c.x+4.75)/9.5,(c.z+.2)/2 if axis=='X' else (c.y+4)/8))
 def ellipsoid(name,loc,scale,mat):
  bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,location=loc)
  ob=bpy.context.object;ob.name=name;ob.scale=scale;ob.data.materials.append(mat);aircraft.append(ob)
  if mat==paint:
   for loop in ob.data.uv_layers.active.data: loop.uv=uvband(0,loop.uv.x,loop.uv.y)
  return ob
 def propeller(x,y,r,label):
  pivot=bpy.data.objects.new('Propeller_'+label,None);s.collection.objects.link(pivot);pivot.location=(x,y,0)
  aircraft.append(pivot)
  bpy.context.view_layer.update()
  for k in range(3):
   a=k*2*pi/3+.2
   outline=[]
   for t,rad in [(-.06,.15),(-.13,.48),(-.12,r*.86),(-.035,r),(.06,r),(.16,r*.75),(.13,.38)]:
    outline.append((x+t*cos(a)+rad*sin(a),y+t*.15,rad*cos(a)-t*sin(a)))
   ob=solid('Prop_blade',outline,axis='Y',thick=.022,mat=dark)
   matrix=ob.matrix_world.copy();ob.parent=pivot;ob.matrix_world=matrix
   tip=tube('Prop_tip',[(x+r*.9*sin(a),y-.027,r*.9*cos(a)),(x+r*.98*sin(a),y-.027,r*.98*cos(a))],.065,yellow)
   matrix=tip.matrix_world.copy();tip.parent=pivot;tip.matrix_world=matrix
  ellipsoid('Spinner',(x,y-.08,0),(.19,.31,.19),yellow if kind=='p38' else steel)
  return pivot
 def canopy(y0,length,width,base):
  sections=[(0,.35,.12),(.16,.85,.43),(.47,1,.56),(.8,.83,.42),(1,.24,.08)]
  v=[]
  for t,w,h in sections:
   y=y0+t*length
   v += [(-width*w,y,base),(-width*w*.76,y,base+h*.85),(0,y,base+h),(width*w*.76,y,base+h*.85),(width*w,y,base)]
  faces=[(k*5+j,k*5+j+1,(k+1)*5+j+1,(k+1)*5+j) for k in range(4) for j in range(4)]
  mesh('Canopy',v,faces,glass)
  for k in range(5):tube('Canopy_frame',v[k*5:k*5+5],.018,frame)
  for j in [0,2,4]:tube('Canopy_frame',[v[k*5+j] for k in range(5)],.014,frame)
 # Airfoils: actual thickness and elevation at each span station.
 if kind=='p38':
  stations=[(.0,-1.23,.82,.0,.14),(1.6,-1.17,.70,.04,.13),(3.8,-.94,.27,.12,.08),(4.55,-.73,.02,.17,.04),(4.75,-.42,-.20,.19,.015)]
 else:
  stations=[(.0,-1.18,1.18,-.14,.17),(.55,-1.18,1.15,-.26,.16),(1.50,-1.10,1.08,-.72,.14),(2.3,-.99,.92,-.48,.12),(4.25,-.70,.30,.08,.07),(4.65,-.51,.06,.17,.04),(4.75,-.25,-.10,.19,.012)]
 def wingheight(x,y,bottom=False):
  x=abs(x)
  for a,b in zip(stations,stations[1:]):
   if a[0]<=x<=b[0]:
    t=(x-a[0])/(b[0]-a[0]);lead,trail,z,th=[a[i]+t*(b[i]-a[i]) for i in range(1,5)]
    q=max(0,min(1,(y-lead)/(trail-lead)))
    return z+(-.6 if bottom else 1)*th*sin(pi*q)**.65
  return .0
 for sign in [-1,1]:
  chords=[0,.10,.3,.65,.85,1];v=[];uvs=[]
  for bottom in [False,True]:
   for x,lead,trail,z,th in stations:
    for t in chords:
     y=lead+(trail-lead)*t;v.append((sign*x,y,wingheight(x,y,bottom)))
     uvs.append(uvband(1 if bottom else 0,x/4.75,t))
  row=6;half=len(stations)*row
  faces=[]
  for surface in range(2):
   for j in range(len(stations)-1):
    for k in range(5):
     a=surface*half+j*row+k;face=(a,a+1,a+row+1,a+row)
     faces.append(face if (sign<0)!=bool(surface) else tuple(reversed(face)))
  for j in range(len(stations)-1):
   for k in [0,5]:a=j*row+k;b=(j+1)*row+k;faces.append((a,b,b+half,a+half))
  faces.append(tuple(range(half-6,half))+tuple(reversed(range(half*2-6,half*2))))
  ob=mesh('Wing_L' if sign<0 else 'Wing_R',v,faces)
  for poly in ob.data.polygons:
   for li in poly.loop_indices:ob.data.uv_layers[0].data[li].uv=uvs[ob.data.loops[li].vertex_index]
  for x in [2.25,3.55]:
   points=[(sign*x,y,wingheight(x,y)+.007) for y in [-.65,-.3,.0,.24]]
   tube('Wing_access_seam',points,.004,dark)
  # Curved surface-conforming US star-and-bars, geometry rather than painted lighting.
  for bottom in [False,True]:
   if (sign<0 and bottom) or (sign>0 and not bottom):continue
   cx=sign*3.15;cy=-.21
   def patch(name,coords,mat,offset):
    return mesh(name,[(cx+x,cy+y,wingheight(cx+x,cy+y,bottom)+(-offset if bottom else offset)) for x,y in coords],[tuple(range(len(coords)))],mat)
   patch('Insignia_bars',[(-.83,-.17),(.83,-.17),(.83,.17),(-.83,.17)],navy,.009)
   patch('Insignia_bar_white',[(-.77,-.115),(.77,-.115),(.77,.115),(-.77,.115)],white,.012)
   patch('Insignia_roundel',[(.43*sin(i*2*pi/32),.43*cos(i*2*pi/32)) for i in range(32)],navy,.015)
   patch('Insignia_star',[( (.39 if i%2==0 else .16)*sin(i*pi/5),-(.39 if i%2==0 else .16)*cos(i*pi/5)) for i in range(10)],white,.019)
 if kind=='p38':
  body('Cockpit_nacelle',[(-3.32,.05,.08,0),(-3.10,.25,.28,0),(-2.50,.38,.37,.03),(-1.70,.44,.41,.04),(-.75,.40,.35,.02),(.20,.24,.23,0),(.85,.02,.04,0)])
  canopy(-2.02,1.65,.36,.32)
  # Olive anti-glare strip ahead of cockpit, following the nose curvature.
  mesh('Anti_glare',[(-.22,-3.03,.23),(.22,-3.03,.23),(.33,-2.10,.42),(-.33,-2.10,.42)],[(0,1,2,3)],paint,2,uv=lambda c,p:uvband(2,(c.y+3.1)/1.1,(c.x+.4)/.8))
  for sign in [-1,1]:
   x=sign*1.55
   body('Engine_boom',[(-2.73,.24,.24,0),(-2.50,.36,.39,0),(-1.83,.38,.45,-.03),(-.90,.34,.36,0),(.12,.29,.3,.02),(1.2,.21,.21,.06),(2.2,.13,.14,.08),(3.25,.07,.10,.1),(3.46,.025,.04,.1)],x)
   ellipsoid('Chin_intake',(x,-2.22,-.34),(.26,.46,.22),paint)
   ellipsoid('Intake_dark',(x,-2.59,-.32),(.18,.015,.14),dark)
   ellipsoid('Turbocharger',(x,.0,.32),(.14,.31,.09),steel)
   tube('Exhaust',[(x,.05,.34),(x,.48,.29)],.052,steel)
   solid('Twin_tail_fin',[(x,2.12,.14),(x,2.20,.69),(x,2.54,1.36),(x,2.82,1.53),(x,3.04,1.38),(x,3.33,.19)],'X',.05)
   propeller(x,-2.82,1.1,'L' if sign<0 else 'R')
  solid('Joined_tailplane',[(-1.83,2.52,.18),(1.83,2.52,.18),(1.89,3.14,.18),(1.60,3.40,.18),(-1.60,3.40,.18),(-1.89,3.14,.18)])
  for x,z in [(-.17,.12),(.17,.12),(-.10,.26),(.10,.26)]:tube('Nose_gun',[(x,-3.20,z),(x,-3.52,z)],.025,dark)
 else:
  body('Fuselage',[(-3.48,.57,.58,0),(-3.20,.65,.65,0),(-2.50,.63,.64,0),(-1.80,.56,.59,0),(-.85,.50,.53,0),(.25,.43,.48,.04),(1.23,.34,.38,.07),(2.35,.20,.24,.09),(3.45,.055,.095,.1),(3.75,.025,.035,.1)])
  ellipsoid('Radial_engine',(0,-3.50,0),(.54,.035,.54),dark)
  for i in range(14):
   a=i*2*pi/14;tube('Radial_cylinder',[(.18*sin(a),-3.54,.18*cos(a)),(.46*sin(a),-3.54,.46*cos(a))],.065,steel)
  canopy(-.60,1.75,.37,.43)
  propeller(0,-3.68,1.54,'Center')
  solid('Tail_fin',[(0,2.0,.17),(0,2.3,.67),(0,2.53,1.42),(0,2.77,1.64),(0,3.02,1.57),(0,3.37,.86),(0,3.56,.14)],'X',.06)
  for sign in [-1,1]:
   solid('Tailplane',[(sign*.1,2.38,.12),(sign*1.3,2.66,.12),(sign*1.73,2.97,.12),(sign*1.68,3.26,.12),(sign*1.3,3.43,.12),(sign*.1,3.43,.12)])
   for x in [1.86,2.10,2.34]:tube('Wing_gun',[(sign*x,-.93,wingheight(x,-.93)),(sign*x,-1.21,wingheight(x,-.93))],.026,dark)
  tube('Antenna',[(0,1.32,.45),(0,1.4,1.10)],.015,frame)
 # Correct winding independently of constructive order, export two-sided insignia.
 import bmesh
 for ob in aircraft:
  if ob.type!='MESH':continue
  bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(ob.data);bm.free()
 # Merge static geometry by material; retain each rotating propeller branch.
 groups={}
 for ob in aircraft:
  if ob.type=='MESH':groups.setdefault((ob.data.materials[0].name,ob.parent.name if ob.parent else ''),[]).append(ob)
 for (mat,parent),obs in groups.items():
  bpy.ops.object.select_all(action='DESELECT')
  for ob in obs:ob.select_set(True)
  bpy.context.view_layer.objects.active=obs[0]
  if len(obs)>1:bpy.ops.object.join()
  bpy.context.object.name=(parent+'_' if parent else '')+mat
 export_objects=[ob for ob in s.objects if ob.type=='MESH' or ob.name.startswith('Propeller_')]
 bpy.ops.object.select_all(action='DESELECT')
 for ob in export_objects:ob.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(DEST/f'{kind}.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False)
 triangles=0
 for ob in export_objects:
  if ob.type=='MESH':ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
 # Pack source artwork and references with editable materials in the source file.
 ref=bpy.data.objects.new('REFERENCE_CONCEPT',None);s.collection.objects.link(ref);ref.empty_display_type='IMAGE';ref.data=bpy.data.images.load(str(ROOT/f'art/player-fleet/{kind}-reference.png'));ref.hide_render=True;ref.hide_viewport=True
 world=bpy.data.worlds.new('Studio HDR');s.world=world;world.use_nodes=True
 n=world.node_tree.nodes;n.clear();out=n.new('ShaderNodeOutputWorld');bg=n.new('ShaderNodeBackground');bg.inputs[1].default_value=.6
 env=n.new('ShaderNodeTexEnvironment');env.image=bpy.data.images.load(str(ROOT/'blender/studio_small_07_4k.exr'))
 world.node_tree.links.new(env.outputs['Color'],bg.inputs[0]);world.node_tree.links.new(bg.outputs[0],out.inputs[0])
 flat=n.new('ShaderNodeBackground');flat.inputs[0].default_value=(.18,.22,.27,1);flat.inputs[1].default_value=.65
 path=n.new('ShaderNodeLightPath');mix=n.new('ShaderNodeMixShader');world.node_tree.links.new(path.outputs['Is Camera Ray'],mix.inputs[0]);world.node_tree.links.new(bg.outputs[0],mix.inputs[1]);world.node_tree.links.new(flat.outputs[0],mix.inputs[2]);world.node_tree.links.new(mix.outputs[0],out.inputs[0])
 for name,loc,energy,color in [('Key',(-5,-7,10),1600,(1,.91,.8)),('Fill',(7,-3,6),1100,(.7,.85,1)),('Rim',(0,6,8),1800,(1,.95,.85)),('Under',(-2,-4,-8),1000,(.8,.9,1))]:
  data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=7;data.color=color
  ob=bpy.data.objects.new(name,data);s.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(-ob.location).to_track_quat('-Z','Y').to_euler()
 data=bpy.data.cameras.new('Studio_camera');cam=bpy.data.objects.new('Studio_camera',data);s.collection.objects.link(cam);s.camera=cam;data.type='ORTHO';data.ortho_scale=11.5
 s.render.engine='CYCLES';s.cycles.samples=32;s.cycles.use_denoising=True
 s.render.resolution_x=1400;s.render.resolution_y=1100;s.render.resolution_percentage=100
 s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.film_transparent=False
 s.view_settings.view_transform='AgX'
 for label,loc in [('top',(0,0,20)),('underside',(0,0,-20)),('front',(10,-15,10))]:
  cam.location=loc;cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
  s.render.filepath=str(OUT/f'{kind}-{label}.png');bpy.ops.render.render(write_still=True)
 s.render.film_transparent=True;s.render.resolution_x=1000;s.render.resolution_y=580;data.ortho_scale=12.7
 s.render.filepath=str(ROOT/('game/assets/campaign/carrier-ui/'+('interceptor' if kind=='p38' else 'bulwark')+'.png'));bpy.ops.render.render(write_still=True)
 bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f'blender/player-fleet/{kind}-studio.blend'))
 (DEST/f'{kind}-report.json').write_text(json.dumps({'triangles':triangles,'meshes':len(groups),'span':9.5,'source_atlas':f'art/player-fleet/{kind}-albedo.png','propellers':2 if kind=='p38' else 1},indent=2))
 print('FLEET COMPLETE',kind,triangles)

for kind in ['p38','f4u']:build(kind)
