"""Authored WWII ground installations. Blender 4.5, single material / two meshes.

Run blender --background --python blender/ground-forces/build_ground_forces.py
Add -- --render to produce the HDR studio asset board (Cycles CPU).
"""
import bpy, math, json, sys, random
from math import sin, cos, pi
from mathutils import Vector
from pathlib import Path

ROOT = Path('C:/ChatGPT/1942')
OUT = ROOT / 'game/assets/ground-forces'
SOURCE = ROOT / 'blender/ground-forces'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
random.seed(1942)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
atlas = bpy.data.images.load(str(OUT / 'field-material-atlas.png'))
atlas.pack()
material = bpy.data.materials.new('Field arsenal | painted steel, canvas, concrete')
material.use_nodes = True
nodes = material.node_tree.nodes
links = material.node_tree.links
bsdf = nodes.get('Principled BSDF')
tex = nodes.new('ShaderNodeTexImage'); tex.image = atlas
colors = nodes.new('ShaderNodeVertexColor'); colors.layer_name = 'FieldFinish'
multiply = nodes.new('ShaderNodeMixRGB'); multiply.blend_type='MULTIPLY'; multiply.inputs[0].default_value=1
links.new(tex.outputs['Color'],multiply.inputs[1]);links.new(colors.outputs['Color'],multiply.inputs[2])
links.new(multiply.outputs['Color'],bsdf.inputs['Base Color'])
links.new(colors.outputs['Alpha'],bsdf.inputs['Metallic'])
bsdf.inputs['Roughness'].default_value=.65
bump = nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.15;bump.inputs['Distance'].default_value=.018
links.new(tex.outputs['Color'],bump.inputs['Height']);links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])

# atlas panels: olive, concrete, corrugated alloy, canvas, steel, wood.
OLIVE,CONCRETE,ROOF,CANVAS,STEEL,WOOD=range(6)
METAL=[.30,.0,.55,.0,.72,.0]
parts={}; current=''; moving=False

def finish(ob, cell=OLIVE, tint=(1,1,1), bevel=0, smooth=False):
    global moving
    ob.name=current+'_'+ob.name
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod=ob.modifiers.new('Machined edge highlights','BEVEL');mod.width=bevel;mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    mesh=ob.data
    if not mesh.uv_layers: mesh.uv_layers.new(name='FieldUV')
    uv=mesh.uv_layers.active
    uv.name='FieldUV'
    # Per-face box projection provides practical texel scale without stretched UVs.
    bounds=[max(abs(v.co[i]) for v in mesh.vertices) or 1 for i in range(3)]
    for p in mesh.polygons:
        axis=max(range(3),key=lambda i:abs(p.normal[i]))
        axes=[i for i in range(3) if i!=axis]
        for li in p.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            u=.5+co[axes[0]]/(2*bounds[axes[0]])
            v=.5+co[axes[1]]/(2*bounds[axes[1]])
            uv.data[li].uv=((cell%3+.025+.95*u)/3,1-(cell//3+.025+.95*(1-v))/2)
        p.use_smooth=smooth
    attr=mesh.color_attributes.new(name='FieldFinish',type='FLOAT_COLOR',domain='CORNER')
    for c in attr.data: c.color=(*tint,METAL[cell])
    mesh.materials.clear();mesh.materials.append(material)
    parts[current][1 if moving else 0].append(ob)
    return ob

def box(name, at, dims, cell=OLIVE, tint=(1,1,1), bevel=.015, rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1,location=at,rotation=rot)
    ob=bpy.context.object;ob.name=name;ob.scale=dims
    return finish(ob,cell,tint,bevel)

def cyl(name, at, radius, depth, cell=STEEL, vertices=16, rot=(0,0,0), tint=(1,1,1), top=None):
    if top is not None:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=top,depth=depth,location=at,rotation=rot)
    else:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=at,rotation=rot)
    ob=bpy.context.object;ob.name=name
    return finish(ob,cell,tint,0,True)

def rod(name, a, b, radius=.025, cell=STEEL, tint=(1,1,1), vertices=8):
    a,b=Vector(a),Vector(b);v=b-a
    ob=cyl(name,(a+b)*.5,radius,v.length,cell,vertices,tint=tint)
    ob.rotation_euler=v.to_track_quat('Z','Y').to_euler()
    return ob

def mesh(name, verts, faces, cell=OLIVE, tint=(1,1,1), smooth=False):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob)
    return finish(ob,cell,tint,0,smooth)

def ring(name, at, outer, inner, height, cell=STEEL, n=24, tint=(1,1,1)):
    x,y,z=at;verts=[]
    for h in [-height/2,height/2]:
        for r in [outer,inner]:
            verts.extend([(x+r*cos(i*2*pi/n),y+r*sin(i*2*pi/n),z+h) for i in range(n)])
    faces=[]
    for i in range(n):
        j=(i+1)%n
        faces.extend([(i,j,2*n+j,2*n+i),(n+i,3*n+i,3*n+j,n+j),(2*n+i,2*n+j,3*n+j,3*n+i),(i,n+i,n+j,j)])
    return mesh(name,verts,faces,cell,tint)

def bag(at,angle=0,scale=1):
    ob=box('Sandbag sewn canvas',at,(.44*scale,.24*scale,.19*scale),CANVAS,bevel=.075*scale,rot=(0,0,angle))
    return ob

def crate(at,scale=.35):
    x,y,z=at
    box('Ammunition crate',at,(scale,scale*.72,scale*.72),WOOD,bevel=.018)
    for offset in [-.33,.33]:
        box('Crate steel strap',(x+offset*scale,y,z),(scale*.035,scale*.74,scale*.77),STEEL,tint=(.6,.63,.57),bevel=0)

def drum(at,r=.13,h=.34):
    x,y,z=at
    cyl('Oil drum',(x,y,z+h*.5),r,h,OLIVE,12)
    for offset in [.05,.29]: ring('Drum rolled seam',(x,y,z+offset*h/.34),r*1.04,r*.94,.018,STEEL,12)
    cyl('Drum fill cap',(x+r*.42,y,z+h+.012),.022,.022,STEEL,8)

def ladder(x,y,z,height,width=.23):
    for dx in [-width*.5,width*.5]:rod('Access ladder rail',(x+dx,y,z),(x+dx,y,z+height),.018)
    for i in range(int(height/.15)+1):rod('Ladder rung',(x-width*.5,y,z+i*.15),(x+width*.5,y,z+i*.15),.012,vertices=6)

def bolts(at,rad,count=12):
    x,y,z=at
    for i in range(count):
        a=2*pi*i/count
        cyl('Foundation bolt',(x+rad*cos(a),y+rad*sin(a),z),.027,.035,STEEL,6,tint=(1.15,1.15,1.10))

def gun_mount(z=.1,twin=True):
    ring('Traverse bearing',(0,0,z+.07),.48,.34,.15,STEEL,24)
    cyl('Pedestal casting',(0,0,z+.28),.30,.42,OLIVE,16,top=.24)
    for x in [-.30,.30]:
        box('Gun cradle',(x,-.08,z+.55),(.14,.47,.39),OLIVE,bevel=.035)
        cyl('Trunnion',(x*1.3,-.10,z+.57),.12,.13,STEEL,12,rot=(0,pi/2,0))
    for x in ([-.13,.13] if twin else [0]):
        box('Breech casing',(x,.12,z+.67),(.18,.57,.21),OLIVE,bevel=.035)
        rod('Recoil cylinder',(x,-.19,z+.61),(x,-.65,z+.79),.085,OLIVE,vertices=12)
        rod('Rifled barrel',(x,-.51,z+.76),(x,-1.14,z+1.0),.046,STEEL,vertices=12)
        rod('Muzzle collar',(x,-1.1,z+.985),(x,-1.23,z+1.035),.068,STEEL,vertices=12)
        rod('Bore dark opening',(x,-1.23,z+1.035),(x,-1.232,z+1.036),.043,STEEL,tint=(.18,.18,.18),vertices=12)
    # Folded shield, gunner's seat, handwheels, sights: functional readable detail.
    for side in [-1,1]:
        box('Angled armored splinter shield',(side*.31,-.38,z+.63),(.40,.07,.45),OLIVE,bevel=.015,rot=(.22,0,side*.20))
        box('Foot platform',(side*.48,.10,z+.21),(.29,.43,.06),STEEL,bevel=.015)
        box('Seat leather pad',(side*.45,.32,z+.40),(.23,.22,.055),WOOD,tint=(.65,.65,.65),bevel=.025)
        rod('Seat support',(side*.45,.31,z+.22),(side*.45,.31,z+.4),.027,OLIVE)
        # Hollow handwheels lie in vertical XZ plane.
        wheel=ring('Elevation handwheel',(0,0,0),.125,.10,.025,STEEL,12)
        wheel.rotation_euler=(pi/2,0,0);wheel.location=(side*.42,.16,z+.64)
        for a in [0,pi/2]:
            rod('Wheel spoke',(side*.42-.1*cos(a),.16,z+.64-.1*sin(a)),(side*.42+.1*cos(a),.16,z+.64+.1*sin(a)),.009,vertices=6)
    rod('Optical sight post',(.0,.14,z+.73),(.0,.14,z+.99),.014)
    rod('Optical rangefinder',(-.14,.14,z+.99),(.14,.14,z+.99),.035)

def battery():
    global moving
    cyl('Recessed gravel bearing',(0,0,.055),.74,.11,CONCRETE,24,tint=(.58,.62,.53))
    bolts((0,0,.125),.60,12)
    for i in range(13):
        a=2*pi*i/15+.22
        if -.9<sin(a)<-.7:continue
        bag((1.10*cos(a),1.10*sin(a),.09),a+pi/2)
        if i%3!=0:bag((1.10*cos(a+.095),1.10*sin(a+.095),.25),a+pi/2+.095)
    for i in range(3):crate((.91,-.30+i*.28,.16),.25)
    for i in range(5):cyl('Spent brass casing',(-.63+i*.12,.66,.048),.022,.18,WOOD,8,rot=(0,pi/2,.2*i),tint=(1.2,1.1,.75))
    moving=True;gun_mount(.11,True);moving=False

def bunker():
    global moving
    # Sloped chamfered walls, separate armored roof and embrasure.
    def outline(w,d,c):return [(-w/2+c,-d/2),(w/2-c,-d/2),(w/2,-d/2+c),(w/2,d/2-c),(w/2-c,d/2),(-w/2+c,d/2),(-w/2,d/2-c),(-w/2,-d/2+c)]
    verts=[]
    for height,w,d in [(0,2.55,1.92),(.71,2.27,1.63),(.91,2.50,1.88)]:
        verts += [(x,y,height) for x,y in outline(w,d,.23)]
    faces=[tuple(range(7,-1,-1)),tuple(range(16,24))]
    for level in range(2):
        for i in range(8):faces.append((level*8+i,level*8+(i+1)%8,(level+1)*8+(i+1)%8,(level+1)*8+i))
    mesh('Reinforced sloped concrete casemate',verts,faces,CONCRETE,tint=(.88,.88,.80))
    box('Embrasure recess',(0,-.906,.43),(1.63,.023,.17),STEEL,tint=(.16,.18,.14),bevel=.005)
    for x in [-.7,.7]:box('Embrasure armor reinforcement',(x,-.926,.43),(.065,.029,.22),STEEL,bevel=.008)
    box('Entry blast door',(.83,.942,.31),(.53,.035,.59),OLIVE,bevel=.01)
    box('Entry hood',(.8,.92,.63),(.65,.22,.06),CONCRETE,bevel=.01)
    for i in range(3):box('Steel door hinge',(.59,.976,.12+i*.2),(.065,.04,.06),STEEL,bevel=.005)
    for x in [-.86,.86]:
        cyl('Roof ventilator',(x,.3,1.03),.11,.20,STEEL,12)
        cyl('Mushroom vent cap',(x,.3,1.15),.16,.06,OLIVE,12,top=.13)
    for i in range(7):bag((-1.31+i*.42,.98,.10),.07)
    for i in range(4):bag((-1.34,-.65+i*.39,.10),pi/2)
    crate((1.30,.49,.17),.32)
    moving=True
    cyl('Turret bearing',(0,-.03,.94),.44,.11,STEEL,24)
    cyl('Cast steel turret',(0,-.03,1.12),.44,.31,OLIVE,24,top=.32)
    cyl('Commander hatch',(0,.02,1.295),.18,.045,STEEL,16)
    box('Hatch grip',(0,.02,1.335),(.11,.025,.02),STEEL,bevel=.005)
    rod('Mantlet',(0,-.29,1.12),(0,-.52,1.12),.14,OLIVE,vertices=16)
    rod('Cannon tube',(0,-.46,1.12),(0,-1.21,1.13),.06,STEEL,vertices=12)
    moving=False

def hut(at,size=(.96,.76,.58)):
    x,y,z=at;w,d,h=size
    box('Field communications cabin',(x,y,z+h*.5),(w,d,h),OLIVE,bevel=.03)
    box('Cabin roof',(x,y,z+h+.045),(w+.12,d+.12,.08),ROOF,bevel=.015)
    box('Cabin door',(x,y-d*.501,z+h*.42),(w*.3,.018,h*.78),WOOD,bevel=.004)
    box('Cabin window',(x+w*.29,y-d*.516,z+h*.63),(w*.18,.019,h*.23),STEEL,tint=(.24,.58,.65),bevel=.002)

def radar():
    global moving
    # Four tapered truss legs: diagonals are real open space, not a solid slab.
    for x in [-1,1]:
        for y in [-1,1]:
            box('Tower concrete foot',(x*.46,y*.46,.055),(.24,.24,.11),CONCRETE,bevel=.025)
            rod('Lattice main leg',(x*.46,y*.46,.1),(x*.22,y*.22,1.49),.045,OLIVE)
    for level in range(3):
        lo=.18+level*.39;hi=lo+.39
        a=.46*(1-lo/2.9);b=.46*(1-hi/2.9)
        for side in [-1,1]:
            rod('Truss cross brace',(-a,side*a,lo),(b,side*b,hi),.019,STEEL)
            rod('Truss cross brace',(a,side*a,lo),(-b,side*b,hi),.019,STEEL)
            rod('Truss cross brace',(side*a,-a,lo),(side*b,b,hi),.019,STEEL)
            rod('Truss cross brace',(side*a,a,lo),(side*b,-b,hi),.019,STEEL)
    box('Service platform',(0,0,1.46),(.66,.66,.08),STEEL,bevel=.01)
    ladder(.37,-.39,.10,1.29,.19)
    hut((-.69,.69,0),(.91,.64,.49))
    box('Radio generator',(.78,.65,.24),(.50,.48,.47),OLIVE,bevel=.05)
    for i in range(5):box('Generator cooling louvre',(.78,.399,.14+i*.045),(.31,.035,.018),STEEL,tint=(.45,.45,.43),bevel=0)
    drum((.93,-.52,0),.13,.32)
    for i in range(4):bag((-.91+i*.32,-.86,.1),.1)
    moving=True
    cyl('Radar rotation bearing',(0,0,1.52),.16,.16,STEEL,16)
    rod('Yagi mast',(0,0,1.55),(0,0,1.95),.045,OLIVE)
    # A broad rectangular WWII mattress antenna with rails, vertical dipoles and struts.
    for z in [1.73,2.22]:rod('Antenna horizontal rail',(-.88,0,z),(.88,0,z),.032,OLIVE)
    for x in [-.88,.88]:rod('Antenna perimeter',(x,0,1.73),(x,0,2.22),.032,OLIVE)
    for i in range(13):
        x=-.84+i*.14
        rod('Antenna dipole',(x,-.018,1.73),(x,-.018,2.22),.009,STEEL,vertices=6)
        rod('Antenna emitter',(x,-.02,1.99),(x,-.26,1.99),.012,STEEL,vertices=6)
    for x in [-.65,.65]:rod('Antenna rear diagonal',(0,.28,1.79),(x,0,2.19),.021,OLIVE)
    rod('Antenna rear spine',(-.7,.28,1.79),(.7,.28,1.79),.02,OLIVE)
    moving=False

def fuel():
    global moving
    for x,y,r,h in [(-.79,-.16,.59,1.12),(.72,.24,.56,.95)]:
        cyl('Tank stone footing',(x,y,.048),r+.05,.096,CONCRETE,24,tint=(.69,.70,.61))
        cyl('Riveted fuel tank',(x,y,.08+h*.5),r,h,OLIVE,24)
        for z in [.15,.08+h*.52,.08+h]:ring('Riveted tank weld band',(x,y,z),r+.018,r-.014,.032,STEEL,24,tint=(.67,.75,.61))
        cyl('Conical rain roof',(x,y,h+.17),r+.025,.18,ROOF,24,top=r*.72)
        cyl('Tank filler hatch',(x,y,h+.28),.13,.075,OLIVE,16)
        rod('Gooseneck vent',(x+.3,y,h+.16),(x+.3,y,h+.45),.024)
        rod('Gooseneck vent bend',(x+.3,y,h+.45),(x+.4,y,h+.45),.024)
        ladder(x,y-r-.034,.12,h+.05,.22)
        for i in range(12):
            a=2*pi*i/12
            cyl('Tank band rivet',(x+(r+.02)*cos(a),y+(r+.02)*sin(a),h+.1),.017,.025,STEEL,6)
        rod('Tank feed pipe',(x,y+r,.29),(x,.94,.29),.055,STEEL,vertices=10)
    rod('Distribution manifold',(-.82,.94,.29),(1.16,.94,.29),.064,STEEL,vertices=12)
    for x in [-.70,.58,1.04]:
        rod('Valve riser',(x,.94,.29),(x,.94,.44),.026)
        ring('Red oxide shutoff wheel',(x,.94,.46),.12,.085,.026,WOOD,12,tint=(1.2,.65,.45))
    for x in [-1.19,-.65,0,.65,1.19]:
        box('Low spill berm',(x,-1.02,.06),(.51,.16,.12),CONCRETE,tint=(.53,.57,.45),bevel=.025)
    drum((1.13,-.61,0));drum((.79,-.86,0),.11,.30)
    crate((-.21,-.99,.17),.32)
    moving=True
    box('Pump motor',(0,.97,.37),(.41,.35,.37),OLIVE,bevel=.045)
    for x in [-.1,0,.1]:box('Pump cooling fin',(x,.97,.565),(.045,.3,.028),STEEL,bevel=.006)
    moving=False

def truck(x,y,scale=.65):
    start=len(parts[current][0])
    box('Truck chassis',(0,0,.25),(.61,1.17,.12),STEEL,tint=(.45,.48,.42),bevel=.025)
    box('Truck cargo bed',(0,.25,.51),(.66,.74,.37),OLIVE,bevel=.02)
    box('Truck canvas hood',(0,.27,.83),(.68,.78,.27),CANVAS,tint=(.66,.75,.55),bevel=.10)
    box('Truck cab',(0,-.40,.57),(.62,.42,.55),OLIVE,bevel=.06)
    box('Truck engine hood',(0,-.73,.43),(.57,.34,.26),OLIVE,bevel=.025)
    box('Truck split windshield',(0,-.622,.71),(.48,.026,.20),STEEL,tint=(.16,.42,.47),bevel=.012)
    box('Truck windscreen pillar',(0,-.644,.71),(.025,.025,.22),OLIVE,bevel=.003)
    box('Truck radiator grill',(0,-.913,.40),(.35,.021,.18),STEEL,tint=(.33,.35,.28),bevel=.008)
    for i in range(5):box('Radiator bars',(-.14+i*.07,-.929,.40),(.018,.02,.17),STEEL,bevel=0)
    box('Truck bumper',(0,-.98,.28),(.71,.08,.07),STEEL,bevel=.015)
    for side in [-1,1]:
        for z in [-.50,.55]:
            cyl('Truck all terrain tire',(side*.34,z,.24),.21,.13,STEEL,12,rot=(0,pi/2,0),tint=(.16,.17,.15))
            cyl('Truck wheel hub',(side*.419,z,.24),.10,.03,OLIVE,12,rot=(0,pi/2,0))
        cyl('Truck headlight',(side*.23,-.923,.51),.06,.027,STEEL,12,rot=(pi/2,0,0),tint=(1.6,1.45,.9))
    for ob in parts[current][0][start:]:
        ob.location=Vector((x,y,0))+ob.location*scale;ob.scale*=scale

def runway():
    global moving
    # Quonset corrugated hangar: arched skin, open entrance, structural ribs.
    cx,cy=-.77,.40;radius=.80;length=1.93;spring=.26
    verts=[];n=18
    for y in [cy-length/2,cy+length/2]:
        for i in range(n+1):
            a=i*pi/n;verts.append((cx+radius*cos(a),y,spring+radius*sin(a)))
    faces=[(i,n+1+i,n+2+i,i+1) for i in range(n)]
    mesh('Curved corrugated hangar roof',verts,faces,ROOF,tint=(.90,.98,.98))
    for side in [-1,1]:box('Hangar low sidewall',(cx+side*.78,cy,.13),(.09,length,.26),CONCRETE,bevel=.01)
    for y in [cy-length/2,cy+length/2,cy-.48,cy+.48]:
        for i in range(12):
            a=i*pi/12;b=(i+1)*pi/12
            rod('Arched roof structural rib',(cx+.807*cos(a),y,spring+.807*sin(a)),(cx+.807*cos(b),y,spring+.807*sin(b)),.018,STEEL,vertices=6)
    # rear wall and retracted sliding doors retain a dark open doorway.
    rear=[(cx-radius,cy+length/2,.02),(cx+radius,cy+length/2,.02)]+[(cx+radius*cos(i*pi/n),cy+length/2,spring+radius*sin(i*pi/n)) for i in range(n+1)]
    mesh('Hangar rear wall',rear,[tuple(reversed(range(len(rear))))],OLIVE)
    box('Hangar shadowed interior',(cx,cy+.35,.20),(1.42,.035,.40),STEEL,tint=(.14,.16,.15),bevel=0)
    for side in [-1,1]:box('Open sliding blast door',(cx+side*.64,cy-length/2-.02,.38),(.25,.065,.76),OLIVE,bevel=.012)
    box('Hangar door lintel',(cx,cy-length/2-.04,.78),(1.52,.065,.055),STEEL,bevel=.01)
    box('Service threshold',(cx,cy-length/2-.10,.025),(1.65,.28,.05),CONCRETE,tint=(.65,.68,.60),bevel=.012)
    # Weathered control tower, catwalk and continuous dark glazing.
    tx,ty=-.96,-1.65
    box('Control tower masonry',(tx,ty,.53),(.57,.58,1.06),CONCRETE,tint=(.87,.89,.80),bevel=.04)
    box('Tower observation floor',(tx,ty,1.02),(.85,.84,.10),STEEL,bevel=.015)
    box('Blue smoked observation glazing',(tx,ty,1.24),(.72,.72,.38),STEEL,tint=(.19,.48,.53),bevel=.015)
    for dx in [-.37,0,.37]:
        for dy in [-.37,.37]:box('Tower window mullion',(tx+dx,ty+dy,1.25),(.028,.03,.38),OLIVE,bevel=.004)
    box('Control tower steel roof',(tx,ty,1.47),(.87,.86,.09),ROOF,bevel=.015)
    rod('Tower radio aerial',(tx+.25,ty,1.51),(tx+.25,ty,2.10),.012,STEEL,vertices=6)
    ladder(tx+.43,ty,.1,.9,.19)
    truck(.92,-.88,.77)
    for i in range(3):crate((.53+i*.37,.97,.19),.36)
    for i in range(3):drum((.53+i*.32,.54,0),.12,.31)
    for i in range(5):
        box('Taxi edge inset marker',(1.78,-1.8+i*.90,.013),(.10,.42,.026),CONCRETE,tint=(1.2,1.13,.73),bevel=.003)
    moving=True
    # Windsock mast and rigid wind-filled canvas reads clearly while cruising.
    rod('Windsock pole',(1.38,1.65,0),(1.38,1.65,1.18),.023,STEEL)
    rod('Windsock swivel',(1.38,1.65,1.18),(1.08,1.65,1.18),.022,STEEL)
    sock=cyl('Canvas windsock',(1.0,1.65,1.13),.105,.50,CANVAS,12,rot=(0,pi/2+.16,0),top=.048,tint=(1.2,.65,.35))
    moving=False

def joined(objects,name):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    ob=bpy.context.object;ob.name=name
    # Zero origin lets Godot rotate the assembly around its true mount center.
    scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    # Only one surface per mesh: all six textures share one atlas and vertex finish.
    for poly in ob.data.polygons:poly.material_index=0
    while len(ob.data.materials)>1:ob.data.materials.pop(index=1)
    ob.data.calc_loop_triangles()
    return ob

report={}; models=[]
for kind,build in [('battery',battery),('bunker',bunker),('radar',radar),('fuel',fuel),('runway',runway)]:
    current=kind;parts[kind]=[[],[]];moving=False;build()
    hull=joined(parts[kind][0],'Hull')
    assembly=joined(parts[kind][1],'Radar' if kind=='radar' else 'Turret')
    root=bpy.data.objects.new(kind.title(),None);scene.collection.objects.link(root)
    hull.parent=root;assembly.parent=root
    for ob in bpy.context.selected_objects:ob.select_set(False)
    for ob in [root,hull,assembly]:ob.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_materials='NONE',export_vertex_color='NAME',export_vertex_color_name='FieldFinish',export_normals=True,export_texcoords=True)
    count=sum(len(ob.data.loop_triangles) for ob in [hull,assembly])
    allpoints=[v.co for ob in [hull,assembly] for v in ob.data.vertices]
    extent=[max(v[i] for v in allpoints)-min(v[i] for v in allpoints) for i in range(3)]
    report[kind]={'triangles':count,'meshes':2,'surfaces':2,'width_depth_height':extent,'file':kind+'.glb'}
    # Release generic export names before building the next installation.
    hull.name=kind+'_Hull';assembly.name=kind+('_Radar' if kind=='radar' else '_Turret')
    models.append(root)

(SOURCE/'build-report.json').write_text(json.dumps(report,indent=2))

# Studio layout retains exact production meshes and materials. No illustrative replacements.
positions=[(-4.0,-2.4,0),(0,-2.4,0),(4.0,-2.4,0),(-2.3,2.5,0),(2.5,2.5,0)]
for model,at in zip(models,positions):model.location=at
floor=bpy.data.materials.new('Studio charcoal');floor.diffuse_color=(.04,.055,.07,1)
bpy.ops.mesh.primitive_plane_add(size=200)
plane=bpy.context.object;plane.name='Studio ground';plane.data.materials.append(floor);plane.location.z=-.015
world=bpy.data.worlds.new('Studio small 07 HDRI');world.use_nodes=True;scene.world=world
env=world.node_tree.nodes.new('ShaderNodeTexEnvironment');env.image=bpy.data.images.load(str(ROOT/'blender/studio_small_07_4k.exr'))
world.node_tree.links.new(env.outputs['Color'],world.node_tree.nodes.get('Background').inputs['Color'])
world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.45
for name,at,power,size,color in [('Key softbox',(-5,-6,10),900,8,(1,.92,.76)),('Sky fill',(5,4,8),650,7,(.71,.85,1))]:
    light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size;light.color=color
    ob=bpy.data.objects.new(name,light);scene.collection.objects.link(ob);ob.location=at;ob.rotation_euler=(Vector((0,0,.5))-ob.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('Asset review camera');camera=bpy.data.objects.new('Asset review camera',camdata);scene.collection.objects.link(camera)
camera.location=(7,-15,16);camera.rotation_euler=(Vector((0,0,.4))-camera.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=13.9;scene.camera=camera
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.resolution_x=2200;scene.render.resolution_y=1650;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=-.3
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(ROOT/'renders/ground-forces-studio.png')
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'ground-forces-studio.blend'))
if '--render' in sys.argv:bpy.ops.render.render(write_still=True)
print('GROUND_FORCES_REPORT',json.dumps(report))
