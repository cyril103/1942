import bpy, math, os, json
from mathutils import Vector
OUT=r'C:/ChatGPT/1942/game/assets/campaign/models'
SOURCE=r'C:/ChatGPT/1942/blender/campaign'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def mat(n,c,metal=0,rough=.5):
 m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 return m
steel=mat('Blue gunmetal',(.14,.18,.19),.65,.38);dark=mat('Rubber and soot',(.025,.03,.028),.1,.8);deck=mat('Weathered deck',(.30,.26,.18),.05,.8);brass=mat('Brass trim',(.48,.32,.1),.6,.4);paint=mat('Olive enamel',(.12,.16,.08),.3,.48);glass=mat('Blue glazing',(.02,.1,.14),.7,.19);white=mat('Deck markings',(.65,.65,.49),.05,.8);red=mat('Signal red',(.4,.02,.014),.2,.55)
def box(n,loc,scale,m):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=n;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
 bevel=o.modifiers.new('Edge bevel','BEVEL');bevel.width=.035;bevel.segments=2;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=bevel.name)
 return o
def cylinder(n,loc,r,depth,m,rot=(0,0,0),vertices=12):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=loc,rotation=rot);o=bpy.context.object;o.name=n;o.data.materials.append(m);return o
def hull(n,width,length,height,m):
 rings=[(-length*.5,.08),(-length*.38,width*.65),(-length*.2,width),(length*.3,width),(length*.48,width*.65)]
 verts=[]
 for y,w in rings:
  verts += [(-w*.45,y,-height*.3),(w*.45,y,-height*.3),(w*.5,y,height*.5),(-w*.5,y,height*.5)]
 faces=[(3,2,1,0)]
 for i in range(len(rings)-1):
  for j in range(4): faces.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
 faces.append(tuple(range((len(rings)-1)*4,len(rings)*4)))
 mesh=bpy.data.meshes.new(n);mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new(n,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(m);return o
def turret(n,x,y,z,heavy=False):
 cylinder(n+'_base',(x,y,z),.48 if heavy else .32,.25,steel)
 box(n+'_housing',(x,y,z+.22),(.85 if heavy else .55,.7,.38),steel)
 for dx in [-.16,.16]: cylinder(n+'_barrel',(x+dx,y-.6,z+.27),.06 if heavy else .035,1.1 if heavy else .8,dark,(math.pi/2,0,0),8)
def export(name):
 bpy.ops.object.select_all(action='DESELECT')
 static=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.parent is None and not o.name.startswith('Fortress_Propeller')]
 for o in static:o.select_set(True)
 if static:
  bpy.context.view_layer.objects.active=static[0];bpy.ops.object.join();static[0].name=name+'_airframe'
 bpy.ops.object.select_all(action='SELECT')
 bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+'.glb'),export_format='GLB',use_selection=True,export_yup=True)
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE,name+'.blend'))
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for kind in ['destroyer','battleship','carrier']:
 w=2.0 if kind=='destroyer' else 3.0;length=12 if kind!='carrier' else 15
 hull(kind+'_hull',w,length,.8,steel)
 hull(kind+'_deck',w*.95,length*.96,.07,deck).location.z=.43
 if kind=='carrier':
  box('Flight deck',(0,0,.65),(4.1,13.5,.16),deck)
  for y in range(-6,7):box('Centre dashed stripe',(.15,y,.746),(.08,.5,.014),white)
  for x in [-1.8,1.8]:box('Runway edge',(x,0,.746),(.06,13.2,.014),white)
  box('Island tower',(1.5,1.6,1.08),(.75,3,.9),steel)
  box('Bridge glazing',(1.5,.4,1.5),(.8,.35,.25),glass)
  for y in [-4,-2,0,2,4]:
   for x in [-1,1]:turret('AA',x*w*.54,y,.6)
 else:
  box('Superstructure',(0,.4,.82),(w*.6,3.0,.8),steel)
  box('Bridge',(0,-.7,1.34),(w*.65,1.0,.65),steel)
  box('Bridge windows',(0,-1.215,1.5),(w*.58,.02,.22),glass)
  for y in [1.6,2.5]:cylinder('Funnel',(0,y,1.35),.34,.9,dark)
  for y in [-3.8,-2.3,4.2]:turret('Main gun',0,y,.6,kind=='battleship')
  for x in [-1,1]:
   for y in [0,2]:turret('AA',x*w*.38,y,.65)
 cylinder('Mast',(0,0,2.0),.045,2.9,steel,vertices=8)
 box('Radar antenna',(0,0,3.2),(1.45,.09,.3),dark)
 for x in [-1,1]:
  for y in [-1,0,1,3]:box('Lifeboat',(x*w*.43,y,.6),(.22,.7,.16),brass)
 for y in [-4.7,4.8]:
  for x in [-1,1]:cylinder('Mooring bollard',(x*.45,y,.5),.09,.14,steel,vertices=8)
 export(kind)
# Develop the textured bomber into a six-engine fortress; preserve baked PBR and propeller pivots.
from mathutils import Matrix
bpy.ops.import_scene.gltf(filepath=r'C:/ChatGPT/1942/blender/bomber/bomber.glb')
roots=[o for o in bpy.context.scene.objects if o.parent is None]
stretch=Matrix.Diagonal((1.35,.92,1.0,1.0))
for root in roots:root.matrix_world=stretch@root.matrix_world
for x in [-8.1,-5.4,5.4,8.1]:
 cylinder('Additional radial engine',(x,-3.8,-.03),.47,2.2,paint,(math.pi/2,0,0))
 cylinder('Additional engine cowling',(x,-4.9,-.03),.49,.24,dark,(math.pi/2,0,0))
 prop=box('Fortress_Propeller',(x,-5.12,-.03),(.12,.09,1.75),dark)
 blade=box('Cross blade',(x,-5.12,-.03),(1.75,.09,.12),dark)
 blade.parent=prop;blade.matrix_parent_inverse=prop.matrix_world.inverted()
export('fortress')
print('CAMPAIGN MODELS EXPORTED')
