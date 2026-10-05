"""Japanese twin-engine bomber enemy; authored geometry and UVs, generated paint, Cycles HDR.
Blender 4.5+. --preview renders 900px; default renders 2200px.
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector
from math import sin, cos, pi

ROOT = Path('C:/ChatGPT/1942')
OUT = ROOT / 'blender/bomber'
RENDERS = ROOT / 'renders/bomber'
ART = ROOT / 'art/enemies/bomber'
PREVIEW = '--preview' in sys.argv
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
scene = bpy.context.scene
air = bpy.data.collections.new('BOMBER | airframe'); scene.collection.children.link(air)
studio = bpy.data.collections.new('STUDIO | HDR'); scene.collection.children.link(studio)
refs = bpy.data.collections.new('REFERENCES'); scene.collection.children.link(refs)
paint = bpy.data.images.load(str(ART / 'textures/v01/bomber-paint-basecolor.png'))


def move(ob, collection=air):
    for c in list(ob.users_collection): c.objects.unlink(ob)
    collection.objects.link(ob)
    return ob


def material(name, color, rough=.45, metal=0, textured=False):
    m=bpy.data.materials.new(name); m.use_nodes=True
    n=m.node_tree.nodes; links=m.node_tree.links; p=n.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    if textured:
        tex=n.new('ShaderNodeTexImage'); tex.image=paint; tex.label='Generated original / authored UV bands'
        grade=n.new('ShaderNodeHueSaturation');grade.inputs['Value'].default_value=.95
        links.new(tex.outputs['Color'],grade.inputs['Color']);links.new(grade.outputs['Color'],p.inputs['Base Color'])
        p.inputs['Specular IOR Level'].default_value=.25
        bw=n.new('ShaderNodeRGBToBW'); links.new(tex.outputs['Color'],bw.inputs[0])
        remap=n.new('ShaderNodeMapRange'); remap.inputs['From Min'].default_value=0;remap.inputs['From Max'].default_value=1
        remap.inputs['To Min'].default_value=.38;remap.inputs['To Max'].default_value=.57
        links.new(bw.outputs[0],remap.inputs[0]);links.new(remap.outputs[0],p.inputs['Roughness'])
        bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.10;bump.inputs['Distance'].default_value=.009
        noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=170
        bump.inputs['Strength'].default_value=.06;bump.inputs['Distance'].default_value=.005
        links.new(noise.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs[0],p.inputs['Normal'])
        hsv=n.new('ShaderNodeSeparateColor');hsv.mode='HSV';links.new(tex.outputs['Color'],hsv.inputs['Color'])
        metalmap=n.new('ShaderNodeMapRange');metalmap.inputs['From Min'].default_value=.08;metalmap.inputs['From Max'].default_value=.25
        metalmap.inputs['To Min'].default_value=.72;metalmap.inputs['To Max'].default_value=.08
        links.new(hsv.outputs[1],metalmap.inputs[0]);links.new(metalmap.outputs[0],p.inputs['Metallic'])
        tone=n.new('ShaderNodeMapRange');tone.inputs['From Min'].default_value=.08;tone.inputs['From Max'].default_value=.25
        tone.inputs['To Min'].default_value=.92;tone.inputs['To Max'].default_value=.40
        links.new(hsv.outputs[1],tone.inputs[0]);links.new(tone.outputs[0],grade.inputs['Value'])
    return m


M_PAINT=material('Paint | generated basecolor, microrelief, roughness',(.08,.12,.08),textured=True)
M_FRAME=material('Canopy enamel',(.035,.045,.026),.52,.08)
M_SEAM=material('Panel joints',(.028,.041,.033),.62)
M_DARK=material('Engine recess',(.012,.014,.017),.60)
M_STEEL=material('Engine alloy',(.24,.26,.27),.32,.82)
M_SPINNER=material('Brushed aluminum spinner',(.075,.085,.07),.39,.55)
M_RED=material('Hinomaru vermilion',(.19,.006,.005),.58,.0)
M_RED.node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value=.22
M_IVORY=material('Hinomaru ivory outline',(.73,.72,.61),.5)
M_PROP=material('Propeller brown-black enamel',(.038,.024,.019),.40,.10)
M_YELLOW=material('Blade safety tips',(.72,.43,.048),.43)
M_GLASS=material('Smoky blue glass',(.009,.014,.013),.28,.08)
p=M_GLASS.node_tree.nodes.get('Principled BSDF');p.inputs['Coat Weight'].default_value=.18
p.inputs['Transmission Weight'].default_value=.32;p.inputs['IOR'].default_value=1.45


def uvband(band, u, v):
    edges=[0,.25,.5,.75,1]
    low,high=edges[band],edges[band+1]
    return (.025+.95*max(0,min(1,u)), 1-(low+(high-low)*(.055+.89*max(0,min(1,v)))))


def mesh(name, verts, faces, mat, uvfn=None, smooth=False):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    ob=bpy.data.objects.new(name,data);air.objects.link(ob);data.materials.append(mat)
    if uvfn:
        uv=data.uv_layers.new(name='UV_Paint')
        for poly in data.polygons:
            for li in poly.loop_indices: uv.data[li].uv=uvfn(data.vertices[data.loops[li].vertex_index].co,poly)
    for poly in data.polygons:poly.use_smooth=smooth
    return ob


def bevel(ob, width=.01):
    m=ob.modifiers.new('Edge highlights','BEVEL');m.width=width;m.segments=1
    return ob


def tube(name, points, radius, mat):
    c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.resolution_u=1;c.bevel_depth=radius;c.bevel_resolution=0
    s=c.splines.new('POLY');s.points.add(len(points)-1)
    for p,co in zip(s.points,points):p.co=(*co,1)
    ob=bpy.data.objects.new(name,c);air.objects.link(ob);c.materials.append(mat);return ob


def cylinder(name, radius, depth, location, mat, vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=location,rotation=(pi/2,0,0))
    ob=move(bpy.context.object);ob.name=name;ob.data.materials.append(mat);return ob


# Reference proportions: long glazed fuselage, two radial nacelles, single fin.
rings=[(-6.65,.64,.59,0),(-5.8,.69,.66,0),(-4.6,.72,.70,0),(-2.9,.74,.72,0),(-.6,.69,.67,.02),(1.8,.54,.53,.04),(3.8,.37,.37,.06),(5.5,.23,.25,.09),(6.7,.13,.16,.10),(7.1,.03,.065,.10)]
def loft(name, sections, mat=M_PAINT, offset=0, glass=False):
    n=20
    verts=[(offset+rx*sin(j*2*pi/n),y,zc+rz*cos(j*2*pi/n)) for y,rx,rz,zc in sections for j in range(n)]
    faces=[(k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j) for k in range(len(sections)-1) for j in range(n)]
    faces += [tuple(reversed(range(n))),tuple((len(sections)-1)*n+j for j in range(n))]
    return mesh(name,verts,faces,mat, None if glass else lambda c,p:uvband(1 if p.normal.z<-.38 else 0,(c.y-sections[0][0])/(sections[-1][0]-sections[0][0]),(math.atan2(c.x-offset,c.z)/(2*pi))%1),True)
loft('Bomber fuselage | closed bomb bay',rings)
def body_radius(y):
    for a,b in zip(rings,rings[1:]):
        if a[0]<=y<=b[0]:
            t=(y-a[0])/(b[0]-a[0]);return [a[i]+t*(b[i]-a[i]) for i in [1,2,3]]
    return list(rings[-1][1:])

nose=[(-8.0,.07,.10,0),(-7.86,.29,.30,0),(-7.52,.50,.48,0),(-7.12,.61,.56,0),(-6.65,.64,.59,0)]
loft('Bombardier glazed nose',nose,M_GLASS,glass=True)
for y,rx,rz,zc in nose[1:]:
    tube('Nose circumferential glazing frame',[(rx*sin(j*2*pi/20),y,zc+rz*cos(j*2*pi/20)) for j in range(21)],.018,M_FRAME)
for j in range(0,20,2):
    a=j*2*pi/20
    tube('Nose longitudinal glazing frame',[(rx*sin(a),y,zc+rz*cos(a)) for y,rx,rz,zc in nose],.014,M_FRAME)
# Simplified dark interior makes the nose glazing read clearly in studio and at game scale.
mesh('Nose interior floor',[(-.4,-7.1,-.22),(.4,-7.1,-.22),(.5,-6.6,-.22),(-.5,-6.6,-.22)],[(0,1,2,3)],M_DARK)

stations=[(0,-3.12,1.78,.22),(.18,-3.20,1.21,.21),(.38,-3.23,.51,.18),(.64,-3.24,-.31,.14),(.84,-3.23,-.97,.095),(.94,-3.12,-1.40,.06),(.99,-2.88,-1.67,.025),(1,-2.52,-2.06,.009)]
chords=[0,.055,.17,.35,.60,.82,1]
def wingpoint(sign,s,t,bottom=False):
    for a,b in zip(stations,stations[1:]):
        if a[0]<=s<=b[0]:
            q=(s-a[0])/(b[0]-a[0]);lead,trail,thick=[a[i]+q*(b[i]-a[i]) for i in [1,2,3]];break
    return (sign*(.45+8.05*s),lead+(trail-lead)*t,-.22+.37*s+(-.65 if bottom else 1)*thick*sin(pi*t)**.65)
def wing_z(x,y,bottom=False):
    s=max(0,min(.99999,(abs(x)-.45)/8.05));lead=wingpoint(1,s,0)[1];trail=wingpoint(1,s,1)[1]
    return wingpoint(1,s,max(0,min(1,(y-lead)/(trail-lead))),bottom)[2]
for sign in [-1,1]:
    vertices=[wingpoint(sign,s,t,bottom) for bottom in [False,True] for s,*_ in stations for t in chords]
    row=len(chords);half=row*len(stations);faces=[]
    for surface in range(2):
        for k in range(len(stations)-1):
            for j in range(row-1):
                a=surface*half+k*row+j;quad=(a,a+1,a+row+1,a+row)
                faces.append(quad if (sign<0)!=bool(surface) else tuple(reversed(quad)))
    for k in range(len(stations)-1):
        for edge in [0,row-1]:
            a=k*row+edge;b=(k+1)*row+edge;faces.append((a,b,half+b,half+a))
    for k in [0,len(stations)-1]:
        for j in range(row-1):
            a=k*row+j;faces.append((a,a+1,a+1+half,a+half))
    ob=mesh('Wing L' if sign<0 else 'Wing R',vertices,faces,M_PAINT)
    uv=ob.data.uv_layers.new(name='UV_Wing')
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            vi=ob.data.loops[li].vertex_index;surface=vi//half;local=vi%half
            uv.data[li].uv=uvband(surface,stations[local//row][0],chords[local%row])
    for bottom in [False,True]:
        verts=[]
        for s in [.055,.18,.30,.48,.65]:
            for t in [0,.035,.065]:
                x,y,z=wingpoint(sign,s,t,bottom);verts.append((x,y,z+(-.006 if bottom else .006)))
        mesh('Yellow leading-edge recognition strip',verts,[(i*3+j,i*3+j+1,(i+1)*3+j+1,(i+1)*3+j) for i in range(4) for j in range(2)],M_PAINT,lambda c,p:uvband(3,(abs(c.x)-.5)/5.3,(c.y+3.3)/.5))
    for s in [.37,.63,.85]:
        tube('Wing panel seam',[(x,y,z+.007) for x,y,z in [wingpoint(sign,s,t) for t in [.12,.35,.6,.8]]],.005,M_SEAM)
    tube('Aileron hinge',[(x,y,z+.008) for x,y,z in [wingpoint(sign,s,.82) for s in [.44,.64,.84,.94]]],.008,M_SEAM)
    for bottom in [False,True]:
        cx,cy=sign*6.15,-2.05
        for radius,mat,lift in [(.62,M_IVORY,.008),(.59,M_RED,.013)]:
            verts=[(cx,cy,wing_z(cx,cy,bottom)+(-lift if bottom else lift))]
            for j in range(49):
                x=cx+radius*cos(j*2*pi/48);y=cy+radius*sin(j*2*pi/48)
                verts.append((x,y,wing_z(x,y,bottom)+(-lift if bottom else lift)))
            mesh('Wing hinomaru',verts,[(0,j+1,j+2) for j in range(48)],mat)
    # Conforming flank markings on the taper, not floating discs.
    for radius,mat,offset in [(.47,M_IVORY,.01),(.43,M_RED,.016)]:
        coords=[(0,0)]+[(radius*r/4*cos(j*2*pi/32),radius*r/4*sin(j*2*pi/32)) for r in range(1,5) for j in range(32)]
        verts=[]
        for dy,dz in coords:
            y=.7+dy;rx,rz,zc=body_radius(y);z=zc+dz
            verts.append((sign*(rx*math.sqrt(max(.01,1-(dz/rz)**2))+offset),y,z))
        faces=[(0,j+1,(j+1)%32+1) for j in range(32)]
        for r in range(3):
            for j in range(32):
                a=1+r*32+j;b=1+r*32+(j+1)%32;faces.append((a,b,b+32,a+32))
        mesh('Fuselage hinomaru',verts,faces,mat)

# Separate port and starboard propellers, with stable local rotation axes.
for side in [-1,1]:
    xoff=side*2.62
    loft('Engine nacelle', [(-4.78,.61,.61,-.04),(-4.35,.65,.65,-.04),(-3.3,.59,.59,-.03),(-2.25,.45,.44,-.03),(-1.25,.24,.28,-.03),(-.65,.035,.09,-.03)],offset=xoff)
    verts=[(xoff+r*sin(j*2*pi/24),y,-.04+r*cos(j*2*pi/24)) for y,r in [(-5.10,.48),(-5.06,.63),(-4.72,.67),(-4.23,.64)] for j in range(24)]
    faces=[(k*24+j,k*24+(j+1)%24,(k+1)*24+(j+1)%24,(k+1)*24+j) for k in range(3) for j in range(24)]
    mesh('Radial engine cowling',verts,faces,M_PAINT,lambda c,p:uvband(2,(math.atan2(c.x-xoff,c.z+.04)/(2*pi))%1,(c.y+5.1)/.87),True)
    cylinder('Engine dark cavity',.49,.10,(xoff,-5.05,-.04),M_DARK,24)
    for j in range(9):
        a=j*2*pi/9
        cylinder('Radial cylinder',.10,.10,(xoff+.32*sin(a),-5.12,-.04+.32*cos(a)),M_STEEL,8)
    prop=bpy.data.objects.new('PROPELLER_L' if side<0 else 'PROPELLER_R',None);air.objects.link(prop);prop.location=(xoff,-5.30,-.04)
    outline=[(.06,.18),(.18,.45),(.22,.96),(.14,1.46),(.04,1.60),(-.06,1.59),(-.15,1.39),(-.13,.78),(-.055,.28)]
    for k in range(3):
        a=2*pi*k/3+.10;verts=[]
        for d in [-.022,.022]:
            for tangent,r in outline:verts.append((tangent*cos(a)+r*sin(a),d+tangent*.16,r*cos(a)-tangent*sin(a)))
        n=len(outline);faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
        blade=mesh('Propeller blade',verts,faces,M_PROP);blade.parent=prop
        for d in [-.024,.024]:
            points=[]
            for tangent,r in [(.14,1.46),(.04,1.60),(-.06,1.59),(-.12,1.46)]:points.append((tangent*cos(a)+r*sin(a),d+tangent*.16,r*cos(a)-tangent*sin(a)))
            cap=mesh('Propeller yellow tip',points,[(0,1,2,3)],M_YELLOW);cap.parent=prop
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,location=(xoff,-5.37,-.04))
    spinner=move(bpy.context.object);spinner.name='Propeller spinner';spinner.scale=(.24,.34,.24);spinner.data.materials.append(M_SPINNER)
    bpy.context.view_layer.update();matrix=spinner.matrix_world.copy();spinner.parent=prop;spinner.matrix_world=matrix
    for poly in spinner.data.polygons:poly.use_smooth=True
    for y in [-4.05,-3.85]:
        ob=cylinder('Exhaust outlet',.07,.15,(xoff+side*.58,y,-.2),M_STEEL,8);ob.rotation_euler=(0,pi/2,0)
    tube('Nacelle closed gear door',[(xoff-.25,-3.7,-.61),(xoff+.25,-3.7,-.61),(xoff+.2,-2.4,-.45),(xoff-.2,-2.4,-.45),(xoff-.25,-3.7,-.61)],.009,M_SEAM)

# Horizontal tail and tall rounded single fin.
for sign in [-1,1]:
    outline=[(.09,4.7),(.9,4.35),(2.9,4.75),(3.83,5.10),(4.02,5.46),(3.87,5.78),(2.7,6.00),(.08,6.20)]
    n=len(outline);verts=[(sign*x,y,.18+z) for z in [-.065,.065] for x,y in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
    bevel(mesh('Horizontal tail',verts,faces,M_PAINT,lambda c,p:uvband(0 if c.z>.18 else 1,abs(c.x)/4.1,(c.y-4.3)/2.0)),.022)
    tube('Elevator hinge',[(sign*.25,5.7,.251),(sign*3.6,5.53,.251)],.008,M_SEAM)
outline=[(3.42,.30),(4.25,.78),(4.90,2.10),(5.30,2.68),(5.6,2.90),(5.83,2.84),(6.03,2.43),(6.16,.22)]
n=len(outline);verts=[(x,y,z) for x in [-.065,.065] for y,z in outline]
faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
bevel(mesh('Single vertical fin',verts,faces,M_PAINT,lambda c,p:uvband(0,(c.y-3.4)/2.8,(c.z-.22)/2.7)),.025)
for side in [-1,1]:tube('Rudder hinge',[(side*.073,5.6,2.6),(side*.073,5.85,.4)],.008,M_SEAM)

sections=[(-5.95,.40,.52,.69),(-5.48,.47,.57,1.04),(-4.85,.48,.58,1.17),(-4.05,.47,.57,1.16),(-3.3,.42,.57,1.02),(-2.83,.34,.54,.77)]
cv=[]
for y,w,base,top in sections:cv += [(-w,y,base),(-w*.80,y,top-.12),(0,y,top),(w*.80,y,top-.12),(w,y,base)]
faces=[(k*5+j,k*5+j+1,(k+1)*5+j+1,(k+1)*5+j) for k in range(len(sections)-1) for j in range(4)]
mesh('Framed cockpit glazing',cv,faces,M_GLASS)
for k in range(len(sections)):tube('Cockpit transverse frame',cv[k*5:k*5+5],.023,M_FRAME)
for j in range(5):tube('Cockpit longitudinal frame',[cv[k*5+j] for k in range(len(sections))],.018,M_FRAME)
# Closed underside bomb bay, flush to the fuselage.
for x in [-.29,0,.29]:
    points=[]
    for y in [-2.6,-1.5,-.4,.7]:
        rx,rz,zc=body_radius(y);points.append((x,y,zc-rz*math.sqrt(1-(x/rx)**2)-.01))
    tube('Closed bomb bay longitudinal seam',points,.009,M_SEAM)
for y in [-2.6,.7]:
    rx,rz,zc=body_radius(y);tube('Closed bomb bay transverse seam',[(x,y,zc-rz*math.sqrt(1-(x/rx)**2)-.011) for x in [-.29,-.15,0,.15,.29]],.009,M_SEAM)
tube('Radio mast',[(0,-2.65,.65),(0,-2.6,1.22)],.022,M_FRAME)
tube('Antenna wire',[(0,-2.6,1.22),(0,5.58,2.86)],.004,M_DARK)
# Compact rear observation glazing.
loft('Tail observation glazing',[(6.48,.15,.18,.1),(6.92,.10,.13,.1),(7.22,.025,.045,.1)],M_GLASS,glass=True)
for side in [-1,1]:tube('Tail glazing frame',[(side*.14,6.5,.12),(side*.09,6.92,.12),(0,7.23,.12)],.012,M_FRAME)

for ob in air.objects:
    if ob.type=='MESH':
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()

# Pack concept and real local HDR. Neutral background is visible only to camera.
ref=bpy.data.objects.new('Bomber three-view reference',None);refs.objects.link(ref)
ref.empty_display_type='IMAGE';ref.data=bpy.data.images.load(str(ART/'bomber-reference-v01.png'));ref.empty_display_size=12
ref.location=(15,0,0);ref.hide_render=True;refs.hide_viewport=True
world=bpy.data.worlds.new('Studio HDR 4K');scene.world=world;world.use_nodes=True
n=world.node_tree.nodes;n.clear();l=world.node_tree.links
env=n.new('ShaderNodeTexEnvironment');env.image=bpy.data.images.load(str(ROOT/'blender/studio_small_07_4k.exr'))
bg=n.new('ShaderNodeBackground');bg.inputs['Strength'].default_value=.45;l.new(env.outputs['Color'],bg.inputs['Color'])
flat=n.new('ShaderNodeBackground');flat.inputs['Color'].default_value=(.61,.65,.68,1);flat.inputs['Strength'].default_value=1
path=n.new('ShaderNodeLightPath');mix=n.new('ShaderNodeMixShader');out=n.new('ShaderNodeOutputWorld')
l.new(path.outputs['Is Camera Ray'],mix.inputs[0]);l.new(bg.outputs[0],mix.inputs[1]);l.new(flat.outputs[0],mix.inputs[2]);l.new(mix.outputs[0],out.inputs[0])
for name,loc,power,size,color in [('Key',(-4,-6,8),2200,10,(1,.97,.92)),('Fill',(5,-2,5),1800,10,(.80,.89,1)),('Rim',(1,6,7),2400,9,(1,.98,.92)),('Under',(-2,-4,-7),2000,10,(.90,.95,1))]:
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=color
    ob=bpy.data.objects.new(name,d);studio.objects.link(ob);ob.location=loc;ob.rotation_euler=(-ob.location).to_track_quat('-Z','Y').to_euler()

cams=[]
for name,loc,rot,scale in [('01 DESSUS',(0,0,30),(0,0,pi),19.0),('02 DESSOUS',(0,0,-30),(pi,0,0),19.0),('03 TROIS QUARTS',(15,-23,15),None,20.0)]:
    d=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,d);studio.objects.link(ob);ob.location=loc;d.type='ORTHO';d.ortho_scale=scale
    ob.rotation_euler=rot if rot else (Vector((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler();cams.append(ob)
scene.render.engine='CYCLES';scene.cycles.samples=24 if PREVIEW else 96;scene.cycles.use_denoising=True;scene.cycles.max_bounces=6
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='CUDA';prefs.get_devices()
    for d in prefs.devices:d.use=d.type=='CUDA'
    if any(d.use for d in prefs.devices):scene.cycles.device='GPU'
except Exception as e:print('Cycles CPU fallback',e)
if hasattr(scene.cycles,'denoising_use_gpu'):scene.cycles.denoising_use_gpu=True
scene.render.resolution_x=scene.render.resolution_y=900 if PREVIEW else 2200
scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
scene.camera=cams[2];scene['asset_notes']='Bomber-inspired stylized low-poly enemy; generated paint texture + authored geometry and insignia. Nose -Y.'
for img in bpy.data.images:
    if img.source=='FILE':img.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bomber-studio.blend'))
stats={'base_triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in air.objects if o.type=='MESH'),
       'mesh_objects':sum(o.type=='MESH' for o in air.objects),'render_engine':'Cycles','samples':scene.cycles.samples,'resolution':scene.render.resolution_x}
(OUT/'build-report.json').write_text(json.dumps(stats,indent=2))
for cam,name in zip(cams,['01-dessus','02-dessous','03-trois-quarts']):
    scene.camera=cam;scene.render.filepath=str(RENDERS/(name+('-preview' if PREVIEW else '')+'.png'));bpy.ops.render.render(write_still=True)
scene.camera=cams[2];bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bomber-studio.blend'))
print('BOMBER COMPLETE',stats)
