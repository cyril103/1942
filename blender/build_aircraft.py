import bpy, math, os, json, sys, bmesh
from mathutils import Vector
from math import sin, cos, pi

ROOT = r'C:/ChatGPT/1942'
OUT = ROOT + '/blender'
RENDERS = ROOT + '/renders'
TEX = ROOT + '/art/aircraft/textures/v01/'
PREVIEW = '--preview' in sys.argv
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in list(bpy.data.materials): bpy.data.materials.remove(block)
scene = bpy.context.scene
air = bpy.data.collections.new('AIRCRAFT | Player 01')
scene.collection.children.link(air)
studio = bpy.data.collections.new('STUDIO | HDR & softboxes')
scene.collection.children.link(studio)
refs = bpy.data.collections.new('REFERENCE | concept board')
scene.collection.children.link(refs)

def move(obj, col=air):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    col.objects.link(obj)
    return obj

atlas = bpy.data.images.load(TEX+'aircraft-atlas-color-source.png')
trim = bpy.data.images.load(TEX+'aircraft-paint-trim-color-source.png')
def mat(name, color, rough=.48, metal=0, image=None):
    m=bpy.data.materials.new(name); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough
    p.inputs['Metallic'].default_value=metal
    if image:
        n=m.node_tree.nodes.new('ShaderNodeTexImage'); n.image=image
        n.interpolation='Linear'; n.label='Original generated source / custom UV'
        hue=m.node_tree.nodes.new('ShaderNodeHueSaturation')
        hue.inputs['Saturation'].default_value=1.10
        hue.inputs['Value'].default_value=.68
        m.node_tree.links.new(n.outputs['Color'],hue.inputs['Color'])
        m.node_tree.links.new(hue.outputs['Color'],p.inputs['Base Color'])
    return m
M_ATLAS=mat('01 | Aircraft atlas / sRGB',(.2,.23,.09),.56,0,atlas)
M_TRIM=mat('02 | Enamel trim / sRGB',(.2,.23,.09),.48,0,trim)
M_FRAME=mat('03 | Canopy frames / olive enamel',(.145,.165,.066),.36)
M_DARK=mat('04 | Engine recess',(.012,.016,.018),.53,.2)
M_METAL=mat('05 | Machined steel',(.20,.24,.27),.29,.85)
M_BRONZE=mat('06 | Prop hub / warm metal',(.25,.17,.065),.3,.8)
M_WHITE=mat('07 | Identification ivory',(.79,.79,.71),.48)
M_SEAM=mat('08 | Panel recesses',(.055,.063,.033),.65)
M_GLASS=mat('09 | Blue canopy glass',(.014,.060,.11),.15,.12)
p=M_GLASS.node_tree.nodes.get('Principled BSDF')
p.inputs['Coat Weight'].default_value=.65
p.inputs['Coat Roughness'].default_value=.09
p.inputs['Transmission Weight'].default_value=.12
p.inputs['IOR'].default_value=1.45
M_RED=mat('10 | Port navigation lens',(.5,.012,.008),.2)
M_GREEN=mat('11 | Starboard navigation lens',(.015,.3,.1),.2)

def mesh(name, verts, faces, material, uvfn=None, smooth=False):
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    ob=bpy.data.objects.new(name,me); air.objects.link(ob); me.materials.append(material)
    if uvfn:
        uv=me.uv_layers.new(name='UV_Authored')
        for poly in me.polygons:
            for li in poly.loop_indices:
                uv.data[li].uv=uvfn(me.vertices[me.loops[li].vertex_index].co, poly)
    for poly in me.polygons: poly.use_smooth=smooth
    return ob

def trim_uv(band, u, v):
    return (.06+.88*u, 1-((band+.13+.74*v)/4))

def bevel(ob, width=.015):
    m=ob.modifiers.new('Tiny edge highlight','BEVEL');m.width=width;m.segments=2
    return ob

def tube(name, points, radius, material):
    cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D'
    cu.resolution_u=1;cu.bevel_depth=radius;cu.bevel_resolution=1
    sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
    for p,co in zip(sp.points,points):p.co=(*co,1)
    ob=bpy.data.objects.new(name,cu);air.objects.link(ob);ob.data.materials.append(material)
    return ob

def cylinder(name, radius, depth, location, material, vertices=16, axis='Y'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=location)
    ob=move(bpy.context.object);ob.name=name
    if axis=='Y':ob.rotation_euler[0]=pi/2
    ob.data.materials.append(material);bevel(ob,.008)
    return ob

# Fuselage: elliptical cross sections, nose points toward -Y.
rings=[(-2.65,.60,.59,.0),(-2.05,.65,.63,0),(-1.25,.60,.60,.015),
       (-.35,.53,.56,.015),(.65,.43,.46,.015),(1.6,.31,.34,.035),
       (2.5,.21,.24,.065),(3.25,.13,.16,.09),(3.65,.035,.065,.10)]
N=16;verts=[]
for y,rx,rz,zc in rings:
    for j in range(N):
        a=j*2*pi/N;verts.append((rx*sin(a),y,zc+rz*cos(a)))
faces=[]
for k in range(len(rings)-1):
    for j in range(N):faces.append((k*N+j,k*N+(j+1)%N,(k+1)*N+(j+1)%N,(k+1)*N+j))
faces.extend([tuple(reversed(range(N))),tuple((len(rings)-1)*N+j for j in range(N))])
def bodyuv(co,poly):
    y=co.y;t=max(0,min(1,(y+2.65)/6.3))
    # Original two flank strips, top and underside mapped to their actual atlas regions.
    idx=min(range(len(rings)),key=lambda i:abs(rings[i][0]-y))
    _,rx,rz,zc=rings[idx]
    zn=(co.z-zc)/rz
    px=140+1015*t
    if co.x>=0: py=470-63*zn
    else: py=667-64*zn
    return(px/1254,1-py/1254)
body=mesh('Fuselage | 16-sided elliptical shell',verts,faces,M_TRIM,
    lambda c,p:trim_uv(1 if p.normal.z < -.25 else 0,(c.y+2.65)/6.3,(math.atan2(c.x,c.z)/(2*pi))%1))
for y,rx,rz,zc in [rings[1],rings[2],rings[5],rings[6]]:
    tube('Fuselage | restrained panel joint', [((rx+.002)*sin(j*2*pi/N),y,zc+(rz+.002)*cos(j*2*pi/N)) for j in range(N+1)],.0035,M_SEAM)

# Cowling, open dark intake, golden leading ring.
def shell(name, sections, band):
    v=[]
    for y,r in sections:
        for j in range(24):
            a=2*pi*j/24;v.append((r*sin(a),y,r*cos(a)))
    f=[]
    for k in range(len(sections)-1):
        for j in range(24):f.append((24*k+j,24*k+(j+1)%24,24*(k+1)+(j+1)%24,24*(k+1)+j))
    low=sections[0][0];high=sections[-1][0]
    return mesh(name,v,f,M_TRIM,lambda c,p:trim_uv(band,(math.atan2(c.x,c.z)/(2*pi))%1,(c.y-low)/(high-low)))
shell('Cowling | olive barrel',[(-3.06,.635),(-2.83,.69),(-2.38,.675),(-2.18,.62)],0)
shell('Cowling | yellow rolled lip',[(-3.23,.53),(-3.24,.60),(-3.14,.66),(-2.98,.66)],2)
cylinder('Radial engine | black cavity',.529,.08,(0,-3.13,0),M_DARK,24)
for j in range(9):
    a=j*2*pi/9;x=.34*sin(a);z=.34*cos(a)
    cylinder('Radial cylinder %02d'%j,.106,.09,(x,-3.20,z),M_METAL,8)
    for k in range(3):
        cylinder('Cooling fin %02d.%02d'%(j,k),.113,.014,(x,-3.245-k*.018,z),M_DARK,8)
cylinder('Propeller shaft',.12,.38,(0,-3.40,0),M_METAL)

# Wing airfoil grids, custom UV sampling of matching original atlas islands.
stations=[(0,-1.56,1.08,.145),(.16,-1.52,1.00,.135),(.47,-1.43,.77,.108),
          (.76,-1.26,.49,.074),(.91,-1.12,.30,.054),(.98,-.93,.12,.032),(1,-.67,-.08,.013)]
chords=[0,.08,.25,.52,.77,1]
def wing(sign):
    v=[];uvs=[]
    for bottom in [False,True]:
        for s,lead,trail,thick in stations:
            for t in chords:
                x=sign*(.40+4.35*s);y=lead+(trail-lead)*t
                z=-.17+.21*s+(1 if not bottom else -.65)*thick*sin(pi*t)**.65
                v.append((x,y,z))
                px=(303-280*s if sign<0 else 334+280*s)+(615 if bottom and sign<0 else 610 if bottom else 0)
                py=(15+20*s**6)*(1-t)+(357-112*s-24*s**8)*t
                uvs.append((px/1254,1-py/1254))
    f=[];row=len(chords);half=len(stations)*row
    for surf in range(2):
        for k in range(len(stations)-1):
            for j in range(row-1):
                a=surf*half+k*row+j;face=(a,a+1,a+row+1,a+row)
                f.append(face if (sign<0) != bool(surf) else tuple(reversed(face)))
    for j in range(row-1):f.append(((len(stations)-1)*row+j,(len(stations)-1)*row+j+1,half+(len(stations)-1)*row+j+1,half+(len(stations)-1)*row+j))
    for k in range(len(stations)-1):
        for edge in [0,row-1]:
            a=k*row+edge;b=(k+1)*row+edge;f.append((a,b,half+b,half+a))
    ob=mesh(('Port' if sign<0 else 'Starboard')+' wing | paint UV',v,f,M_TRIM)
    uv=ob.data.uv_layers.new(name='UV_WingAtlas')
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            vi=ob.data.loops[li].vertex_index
            surf=vi//half;local=vi%half;s=stations[local//row][0];t=chords[local%row]
            uv.data[li].uv=trim_uv(surf,s,t)
    return ob
wing(-1);wing(1)

# Atlas insignia sampled with preserved proportions, separated from wing paint.
decal=mat('12 | Atlas insignia / chroma mask',(.8,.8,.8),.5,0,atlas)
nd=decal.node_tree.nodes;lk=decal.node_tree.links
tex=next(n for n in nd if n.type=='TEX_IMAGE');ps=nd.get('Principled BSDF')
sep=nd.new('ShaderNodeSeparateColor');lk.new(tex.outputs['Color'],sep.inputs[0])
mul=nd.new('ShaderNodeMath');mul.operation='MULTIPLY';mul.inputs[1].default_value=.85;lk.new(sep.outputs[0],mul.inputs[0])
gt=nd.new('ShaderNodeMath');gt.operation='GREATER_THAN';lk.new(sep.outputs[2],gt.inputs[0]);lk.new(mul.outputs[0],gt.inputs[1]);lk.new(gt.outputs[0],ps.inputs['Alpha'])
def wing_z(x,y,bottom=False):
    s=max(0,min(1,(abs(x)-.4)/4.35))
    for i in range(len(stations)-1):
        a,b=stations[i],stations[i+1]
        if a[0]<=s<=b[0]:
            q=(s-a[0])/(b[0]-a[0]);lead=a[1]+q*(b[1]-a[1]);trail=a[2]+q*(b[2]-a[2]);thick=a[3]+q*(b[3]-a[3]);break
    t=max(0,min(1,(y-lead)/(trail-lead)))
    return -.17+.21*s+(-.65 if bottom else 1)*thick*sin(pi*t)**.65+(-.006 if bottom else .006)
for sign in [-1,1]:
    for bottom in [False,True]:
        v=[];du=[]
        for j in range(7):
            for i in range(13):
                u=i/12;t=j/6;x=sign*(2.72+(u-.5)*2.0);y=-.39+(t-.5)*1.30
                v.append((x,y,wing_z(x,y,bottom)))
                du.append(((50+220*u)/1254,1-(92+143*t)/1254))
        f=[]
        for j in range(6):
            for i in range(12):a=j*13+i;f.append((a,a+1,a+14,a+13))
        ob=mesh('Wing insignia | correctly proportioned',v,f,decal)
        uv=ob.data.uv_layers.new(name='UV_Insignia')
        for p in ob.data.polygons:
            for li in p.loop_indices:uv.data[li].uv=du[ob.data.loops[li].vertex_index]
    # Sparse real seams preserve the intended game-scale readability.
    for s in [.28,.70,.91]:
        x=sign*(.4+4.35*s);lead=-1.5+.5*s;trail=1.06-.9*s
        tube('Wing panel joint',[(x,y,wing_z(x,y)+.002) for y in [lead+(trail-lead)*i/10 for i in range(11)]],.004,M_SEAM)
    points=[]
    for i in range(18):
        s=.25+.7*i/17;x=sign*(.4+4.35*s);y=.61-.54*s;points.append((x,y,wing_z(x,y)+.003))
    tube('Aileron hinge',points,.007,M_SEAM)

# Solid tapered tailplane with beveled silhouette.
def tailplane(sign):
    outline=[(.10,2.22),(.62,2.27),(1.55,2.66),(1.77,2.88),(1.72,3.13),(1.48,3.23),(.12,3.33)]
    v=[(sign*x,y,.13+z) for z in [-.047,.047] for x,y in outline]
    n=len(outline);f=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    f += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    ob=mesh(('Port' if sign<0 else 'Starboard')+' horizontal stabilizer',v,f,M_TRIM,
        lambda c,p:trim_uv(0 if c.z>.13 else 1,(abs(c.x)-.1)/1.7,(c.y-2.2)/1.2))
    bevel(ob,.025)
    tube('Elevator hinge',[(sign*.24,3.09,.185),(sign*1.52,3.02,.185)],.007,M_SEAM)
tailplane(-1);tailplane(1)

# Swept, tall fin as in the concept.
outline=[(1.96,.22),(2.36,.62),(2.86,1.43),(3.02,1.60),(3.18,1.62),(3.30,1.48),(3.45,.16)]
v=[(x,y,z) for x in [-.06,.06] for y,z in outline];n=len(outline)
f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
bevel(mesh('Vertical tail | faceted swept fin',v,f,M_TRIM,lambda c,p:trim_uv(0,(c.y-1.96)/1.5,(c.z-.16)/1.5)),.025)
for x in [-.066,.066]:tube('Rudder hinge',[(x,3.16,.26),(x,3.11,1.45)],.007,M_SEAM)

# Rear identification band wraps the actual fuselage, independent of texture stretch.
def band_body(y0,y1):
    def radial(y):
        for i in range(len(rings)-1):
            a,b=rings[i],rings[i+1]
            if a[0]<=y<=b[0]:
                t=(y-a[0])/(b[0]-a[0]);return [a[j]+t*(b[j]-a[j]) for j in [1,2,3]]
    v=[]
    for y in [y0,y1]:
        rx,rz,zc=radial(y)
        for j in range(N):
            a=2*pi*j/N;v.append(((rx+.004)*sin(a),y,zc+(rz+.004)*cos(a)))
    mesh('Identification | ivory rear band',v,[(j,(j+1)%N,(j+1)%N+N,j+N) for j in range(N)],M_WHITE)
band_body(1.66,1.86)

# Canopy with actual faceted glass and structural framing.
sections=[(-1.20,.25,.54,.67),(-.84,.39,.53,1.035),(-.17,.37,.53,1.09),(.42,.30,.46,.95),(.91,.16,.39,.57)]
cv=[]
for y,w,base,top in sections:
    cv.extend([(-w,y,base),(-w*.76,y,top-.105),(0,y,top),(w*.76,y,top-.105),(w,y,base)])
cf=[]
for k in range(len(sections)-1):
    for j in range(4):a=k*5+j;cf.append((a,a+1,a+6,a+5))
cf.extend([(4,3,2,1,0),tuple(20+j for j in range(5))])
mesh('Canopy | blue polygon glass',cv,cf,M_GLASS)
for k in range(len(sections)):tube('Canopy | transverse frame %02d'%k,cv[k*5:k*5+5],.018,M_FRAME)
for j in [0,1,3,4]:tube('Canopy | longitudinal frame %02d'%j,[cv[k*5+j] for k in range(len(sections))],.016,M_FRAME)
tube('Canopy | center spine',[cv[k*5+2] for k in range(len(sections))],.012,M_FRAME)

# Three sculpted propeller blades, yellow tips, stationary for modeling reference.
prop=bpy.data.objects.new('PROPELLER | animate local Y',None);air.objects.link(prop);prop.location=(0,-3.48,0)
outline=[(.06,.17),(.16,.36),(.20,.74),(.15,1.18),(.06,1.34),(-.045,1.35),(-.12,1.21),(-.13,.80),(-.07,.32)]
for k in range(3):
    a=k*2*pi/3+.18;v=[]
    for d in [-.025,.025]:
        for tangent,r in outline:
            v.append((tangent*cos(a)+r*sin(a),d+tangent*.22,r*cos(a)-tangent*sin(a)))
    n=len(outline);f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    ob=mesh('Propeller blade %d'%(k+1),v,f,M_TRIM)
    ob.parent=prop
    uv=ob.data.uv_layers.new(name='UV_Propeller')
    for p in ob.data.polygons:
        for li in p.loop_indices:
            vi=ob.data.loops[li].vertex_index; tangent,r=outline[vi%n]
            # Atlas blade contains yellow tip at left, black body toward right.
            px=700-(r-.17)/1.18*270;py=1037+(tangent+.13)/.33*20
            uv.data[li].uv=(px/1254,1-py/1254)
    ob.data.materials.clear();ob.data.materials.append(M_ATLAS);bevel(ob,.012)
cylinder('Propeller | central collar',.20,.15,(0,-3.48,0),M_METAL,16)
bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,location=(0,-3.61,0))
ob=move(bpy.context.object);ob.name='Propeller | bronze spinner';ob.scale=(.18,.27,.18);ob.data.materials.append(M_BRONZE)

# Small deliberate details, visible in hero and underside views.
for sign in [-1,1]:
    cylinder('Wing gun muzzle',.033,.20,(sign*1.42,-1.52,-.13),M_DARK,8)
    cylinder('Wing gun muzzle',.028,.17,(sign*1.68,-1.50,-.10),M_DARK,8)
    for y in [-1.95,-1.70,-1.45]:
        ob=cylinder('Exhaust stub',.052,.12,(sign*.58,y,-.21),M_METAL,8)
        ob.rotation_euler=(0,pi/2,0)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,location=(sign*4.63,-.76,.04))
    ob=move(bpy.context.object);ob.name='Navigation light';ob.scale=(.08,.095,.045);ob.data.materials.append(M_RED if sign<0 else M_GREEN)
    # Closed landing gear doors: contour follows underside.
    tube('Closed main gear door seam',[(sign*.90,-1.21,-.258),(sign*1.25,-1.19,-.263),(sign*1.41,-.92,-.270),(sign*1.40,-.51,-.249),(sign*1.08,-.32,-.242),(sign*.89,-.55,-.249),(sign*.90,-1.21,-.258)],.007,M_SEAM)
tube('Antenna mast',[(0,.89,.46),(0,.93,.93)],.022,M_FRAME)

# Reference image stays packed in the file but is excluded from rendering.
ref=bpy.data.objects.new('REFERENCE | approved three-view sheet',None);refs.objects.link(ref)
ref.empty_display_type='IMAGE';ref.data=bpy.data.images.load(ROOT+'/art/aircraft/avion-joueur-planche-01.png')
ref.empty_display_size=10;ref.location=(12,0,0);ref.hide_render=True;refs.hide_viewport=True

# Studio HDR, real scene lighting, with neutral background for camera rays.
world=bpy.data.worlds.new('Studio | local 4K HDR');scene.world=world;world.use_nodes=True
nodes=world.node_tree.nodes;nodes.clear();links=world.node_tree.links
env=nodes.new('ShaderNodeTexEnvironment');env.image=bpy.data.images.load(OUT+'/studio_small_07_4k.exr')
bg=nodes.new('ShaderNodeBackground');bg.inputs['Strength'].default_value=.42;links.new(env.outputs['Color'],bg.inputs['Color'])
flat=nodes.new('ShaderNodeBackground');flat.inputs['Color'].default_value=(.92,.89,.82,1);flat.inputs['Strength'].default_value=1.3
path=nodes.new('ShaderNodeLightPath');mix=nodes.new('ShaderNodeMixShader');out=nodes.new('ShaderNodeOutputWorld')
links.new(path.outputs['Is Camera Ray'],mix.inputs[0]);links.new(bg.outputs[0],mix.inputs[1]);links.new(flat.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],out.inputs[0])
def area(name,loc,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    ob=bpy.data.objects.new(name,data);studio.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler()
area('Key | broad warm softbox',(-4,-5,8),1000,6,(1,.92,.80))
area('Fill | cool softbox',(5,-1,5),700,5,(.78,.87,1))
area('Rim | tail separation',(1,6,7),1100,4,(1,.96,.88))
area('Underside | broad fill',(-2,-3,-7),800,6,(.9,.94,1))

def camera(name,loc,scale,rotation=None):
    d=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,d);studio.objects.link(ob)
    ob.location=loc;d.type='ORTHO';d.ortho_scale=scale;d.lens=55
    ob.rotation_euler=rotation if rotation else (Vector((0,-.1,0))-ob.location).to_track_quat('-Z','Y').to_euler()
    return ob
cams=[camera('01 DESSUS',(0,0,20),11.2,(0,0,pi)),camera('02 DESSOUS',(0,0,-20),11.2,(pi,0,0)),camera('03 TROIS QUARTS',(10,-14,10),11.5)]
scene.render.engine='CYCLES';scene.cycles.samples=32 if PREVIEW else 160
scene.cycles.use_denoising=True;scene.cycles.max_bounces=7
scene.cycles.transparent_max_bounces=4
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='CUDA';prefs.get_devices()
    found=False
    for d in prefs.devices:d.use=d.type=='CUDA';found=found or d.type=='CUDA'
    if found:scene.cycles.device='GPU'
except Exception as exc: print('GPU fallback:',exc)
scene.render.resolution_x=900 if PREVIEW else 2200
scene.render.resolution_y=900 if PREVIEW else 2200
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.render.image_settings.color_depth='8'
scene.camera=cams[2]
scene['asset_notes']='Player aircraft based on supplied reference; original atlas and paint trim applied through authored UVs. Local studio_small_07_4k.exr lighting.'
scene['axis_notes']='Nose -Y, wings X, up Z. Separate propeller parent for animation.'
for image in bpy.data.images:
    if image.source=='FILE':image.pack()
for ob in air.objects:
    if ob.type=='MESH':
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
# Open the saved file directly in the hero camera with materials visible.
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D':
            a.spaces.active.region_3d.view_perspective='CAMERA'
            a.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/avion-joueur-studio.blend')
stats={'mesh_objects':sum(o.type=='MESH' for o in air.objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in air.objects if o.type=='MESH'),'renderer':'Cycles','samples':scene.cycles.samples,'resolution':scene.render.resolution_x}
with open(OUT+'/build-report.json','w') as f:json.dump(stats,f,indent=2)
for cam,name in zip(cams,['01-dessus','02-dessous','03-trois-quarts']):
    scene.camera=cam;scene.render.filepath=RENDERS+'/'+name+('-preview' if PREVIEW else '')+'.png'
    bpy.ops.render.render(write_still=True)
scene.camera=cams[2]
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/avion-joueur-studio.blend')
print('AIRCRAFT COMPLETE',stats)
