"""Hayabusa-inspired enemy; authored geometry and UVs, generated paint, Cycles HDR.
Blender 4.5+. --preview renders 900px; default renders 2200px.
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector
from math import sin, cos, pi

ROOT = Path('C:/ChatGPT/1942')
OUT = ROOT / 'blender/hayabusa'
RENDERS = ROOT / 'renders/hayabusa'
ART = ROOT / 'art/enemies/hayabusa'
PREVIEW = '--preview' in sys.argv
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
scene = bpy.context.scene
air = bpy.data.collections.new('HAYABUSA | airframe'); scene.collection.children.link(air)
studio = bpy.data.collections.new('STUDIO | HDR'); scene.collection.children.link(studio)
refs = bpy.data.collections.new('REFERENCES'); scene.collection.children.link(refs)
paint = bpy.data.images.load(str(ART / 'textures/v01/hayabusa-paint-basecolor.png'))


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
        tone.inputs['To Min'].default_value=.92;tone.inputs['To Max'].default_value=.58
        links.new(hsv.outputs[1],tone.inputs[0]);links.new(tone.outputs[0],grade.inputs['Value'])
    return m


M_PAINT=material('Paint | generated basecolor, microrelief, roughness',(.08,.12,.08),textured=True)
M_FRAME=material('Canopy enamel',(.24,.25,.21),.38,.45)
M_SEAM=material('Panel joints',(.028,.041,.033),.62)
M_DARK=material('Engine recess',(.012,.014,.017),.60)
M_STEEL=material('Engine alloy',(.24,.26,.27),.32,.82)
M_SPINNER=material('Brushed aluminum spinner',(.52,.54,.55),.30,.85)
M_RED=material('Hinomaru vermilion',(.19,.006,.005),.58,.0)
M_RED.node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value=.22
M_IVORY=material('Hinomaru ivory outline',(.73,.72,.61),.5)
M_PROP=material('Propeller brown-black enamel',(.038,.024,.019),.40,.10)
M_YELLOW=material('Blade safety tips',(.72,.43,.048),.43)
M_GLASS=material('Smoky blue glass',(.009,.014,.013),.19,.08)
p=M_GLASS.node_tree.nodes.get('Principled BSDF');p.inputs['Coat Weight'].default_value=.4
p.inputs['Transmission Weight'].default_value=.32;p.inputs['IOR'].default_value=1.45


def uvband(band, u, v):
    edges=[0,.285,.547,.778,1]
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


# Slender fuselage, compact radial nose; -Y forward, Z up.
rings=[(-2.75,.55,.54,0),(-2.15,.55,.56,0),(-1.30,.52,.52,.015),(-.35,.46,.49,.02),
       (.55,.385,.425,.015),(1.35,.31,.34,.03),(2.20,.225,.25,.05),(3.05,.14,.16,.08),
       (3.7,.07,.10,.10),(4.00,.018,.04,.10)]
rings=[(y,rx*.90,rz*.94,zc) for y,rx,rz,zc in rings]
N=20
v=[(rx*sin(j*2*pi/N),y,zc+rz*cos(j*2*pi/N)) for y,rx,rz,zc in rings for j in range(N)]
f=[(k*N+j,k*N+(j+1)%N,(k+1)*N+(j+1)%N,(k+1)*N+j) for k in range(len(rings)-1) for j in range(N)]
f += [tuple(reversed(range(N))),tuple((len(rings)-1)*N+j for j in range(N))]
mesh('Fuselage | tapered elliptical shell',v,f,M_PAINT,
     lambda c,p: uvband(1 if p.normal.z<-.38 else 0,(c.y+2.75)/6.75,(math.atan2(c.x,c.z)/(2*pi))%1),True)


def body_radius(y):
    for a,b in zip(rings,rings[1:]):
        if a[0]<=y<=b[0]:
            t=(y-a[0])/(b[0]-a[0]);return [a[i]+t*(b[i]-a[i]) for i in [1,2,3]]
    return list(rings[-1][1:])


def shell(name, sections, band):
    verts=[(r*sin(j*2*pi/24),y,r*cos(j*2*pi/24)) for y,r in sections for j in range(24)]
    faces=[(k*24+j,k*24+(j+1)%24,(k+1)*24+(j+1)%24,(k+1)*24+j) for k in range(len(sections)-1) for j in range(24)]
    return mesh(name,verts,faces,M_PAINT,lambda c,p:uvband(band,(math.atan2(c.x,c.z)/(2*pi))%1,(c.y-sections[0][0])/(sections[-1][0]-sections[0][0])),True)


shell('Cowling | charcoal radial housing',[(-3.48,.46),(-3.48,.53),(-3.38,.62),(-2.9,.65),(-2.58,.60)],2)
cylinder('Engine dark cavity',.47,.09,(0,-3.43,0),M_DARK,24)
for j in range(9):
    a=j*2*pi/9
    cylinder('Radial engine cylinder',.093,.085,(.31*sin(a),-3.49,.31*cos(a)),M_STEEL,8)
    for d in [0,.023]:cylinder('Cooling fin',.10,.008,(.31*sin(a),-3.54-d,.31*cos(a)),M_DARK,8)

# Broad rounded wings with real upper/lower airfoil surfaces and dihedral.
stations=[(0,-1.78,1.00,.13),(.18,-1.75,.92,.14),(.48,-1.58,.61,.115),(.75,-1.36,.35,.09),
          (.89,-1.19,.20,.065),(.96,-1.03,.05,.038),(.99,-.85,-.11,.024),(1,-.60,-.34,.011)]
chords=[0,.055,.17,.35,.6,.82,1]


def wingpoint(sign,s,t,bottom=False):
    for a,b in zip(stations,stations[1:]):
        if a[0]<=s<=b[0]:
            q=(s-a[0])/(b[0]-a[0]);lead,trail,thick=[a[i]+q*(b[i]-a[i]) for i in [1,2,3]];break
    return (sign*(.32+5.48*s),lead+(trail-lead)*t,-.19+.25*s+(-.65 if bottom else 1)*thick*sin(pi*t)**.65)


def wing_z(x,y,bottom=False):
    s=max(0,min(.99999,(abs(x)-.32)/5.48))
    lead=wingpoint(1,s,0)[1];trail=wingpoint(1,s,1)[1]
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
        for j in range(row-1):a=k*row+j;faces.append((a,a+1,a+1+half,a+half))
    ob=mesh('Wing L' if sign<0 else 'Wing R',vertices,faces,M_PAINT,smooth=False)
    uv=ob.data.uv_layers.new(name='UV_Wing')
    for p in ob.data.polygons:
        for li in p.loop_indices:
            vi=ob.data.loops[li].vertex_index;surface=vi//half;local=vi%half
            uv.data[li].uv=uvband(surface,stations[local//row][0],chords[local%row])
    # Thin conforming recognition strip at wing root leading edge, upper/lower.
    for bottom in [False,True]:
        verts=[]
        for s in [.065,.20,.37]:
            for t in [0,.035,.055,.085]:
                x,y,z=wingpoint(sign,s,t,bottom);verts.append((x,y,z+(-.004 if bottom else .004)))
        mesh('Ochre leading-edge identification',verts,[(i*4+j,i*4+j+1,(i+1)*4+j+1,(i+1)*4+j) for i in range(2) for j in range(3)],M_PAINT,
             lambda c,p:uvband(3,(abs(c.x)-.6)/1.9,(c.y+1.8)/.25))
    for s in [.32,.69,.89]:
        points=[]
        for t in [0.13,.32,.55,.78]:
            x,y,z=wingpoint(sign,s,t);points.append((x,y,z+.004))
        tube('Wing panel seam',points,.0035,M_SEAM)
    tube('Aileron hinge',[(x,y,z+.006) for x,y,z in [wingpoint(sign,s,.82) for s in [.45,.60,.75,.88,.94]]],.006,M_SEAM)

# Geometric conforming roundels remain circular instead of stretching with UVs.
for sign in [-1,1]:
    for bottom in [False,True]:
        cx,cy=sign*4.12,-.53
        for radius,mat,lift in ([(.53,M_RED,.008)] if bottom else [(.565,M_IVORY,.006),(.52,M_RED,.010)]):
            verts=[(cx,cy,wing_z(cx,cy,bottom)+(-lift if bottom else lift))]
            for j in range(49):
                x=cx+radius*cos(j*2*pi/48);y=cy+radius*sin(j*2*pi/48)
                verts.append((x,y,wing_z(x,y,bottom)+(-lift if bottom else lift)))
            mesh('Wing hinomaru',verts,[(0,j+1,j+2) for j in range(48)],mat)
    for radius,mat,offset in [(.275,M_IVORY,.014),(.245,M_RED,.019)]:
        coords=[(0,0)]+[(radius*r/4*cos(j*2*pi/32),radius*r/4*sin(j*2*pi/32)) for r in range(1,5) for j in range(32)]
        verts=[]
        for dy,dz in coords:
            y=1.35+dy;z=.08+dz;rx,rz,zc=body_radius(y)
            # Clamp on the surface; disk lies within flank cross-section.
            z=max(z,zc-rz*.92);z=min(z,zc+rz*.92)
            x=sign*(rx*math.sqrt(max(.01,1-((z-zc)/rz)**2))+offset)
            verts.append((x,y,z))
        faces=[(0,j+1,(j+1)%32+1) for j in range(32)]
        for r in range(3):
            for j in range(32):
                a=1+r*32+j;b=1+r*32+(j+1)%32;faces.append((a,b,b+32,a+32))
        mesh('Fuselage hinomaru',verts,faces,mat)

# Rounded tailplane and fin: compact Hayabusa silhouette.
for sign in [-1,1]:
    outline=[(.08,2.45),(.6,2.40),(1.48,2.66),(1.82,2.90),(1.88,3.13),(1.72,3.32),(.70,3.43),(.08,3.48)]
    n=len(outline);verts=[(sign*x,y,.13+z) for z in [-.045,.045] for x,y in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
    bevel(mesh('Horizontal tail',verts,faces,M_PAINT,lambda c,p:uvband(0 if c.z>.13 else 1,abs(c.x)/1.9,(c.y-2.4)/1.1)),.018)
    tube('Elevator seam',[(sign*.22,3.18,.184),(sign*1.67,3.13,.184)],.006,M_SEAM)
outline=[(2.18,.21),(2.57,.43),(2.84,1.13),(3.00,1.55),(3.20,1.72),(3.39,1.72),(3.53,1.52),(3.61,.22)]
n=len(outline);verts=[(x,y,z) for x in [-.045,.045] for y,z in outline]
faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
bevel(mesh('Rounded vertical fin',verts,faces,M_PAINT,lambda c,p:uvband(0,(c.y-2.18)/1.5,(c.z-.21)/1.51)),.02)

# Long framed greenhouse canopy, clearly distinct from player aircraft.
sections=[(-1.37,.25,.47,.58),(-1.03,.33,.48,.96),(-.61,.345,.48,1.035),
          (-.05,.32,.47,1.015),(.52,.27,.40,.90),(1.05,.19,.32,.65),(1.30,.10,.30,.39)]
cv=[]
for y,w,base,top in sections:cv += [(-w,y,base),(-w*.80,y,top-.10),(0,y,top),(w*.80,y,top-.10),(w,y,base)]
faces=[(k*5+j,k*5+j+1,(k+1)*5+j+1,(k+1)*5+j) for k in range(len(sections)-1) for j in range(4)]
mesh('Canopy glass',cv,faces,M_GLASS)
mesh('Cockpit dark interior',[(-.27,-1.1,.49),(.27,-1.1,.49),(.20,.90,.36),(-.20,.90,.36)],[(0,1,2,3)],M_DARK)
for k in range(len(sections)):tube('Canopy transverse frame',cv[k*5:k*5+5],.018,M_FRAME)
for j in [0,1,2,3,4]:tube('Canopy longitudinal frame',[cv[k*5+j] for k in range(len(sections))],.013,M_FRAME)
tube('Radio mast',[(0,1.15,.49),(0,1.20,1.04)],.018,M_FRAME)

# Independent propeller assembly for later animation.
prop=bpy.data.objects.new('PROPELLER',None);air.objects.link(prop);prop.location=(0,-3.69,0)
outline=[(.06,.16),(.18,.45),(.21,.94),(.12,1.37),(.04,1.49),(-.06,1.48),(-.14,1.30),(-.13,.78),(-.055,.26)]
for k in range(3):
    a=2*pi*k/3+.10;verts=[]
    for d in [-.022,.022]:
        for tangent,r in outline:verts.append((tangent*cos(a)+r*sin(a),d+tangent*.16,r*cos(a)-tangent*sin(a)))
    n=len(outline);faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
    blade=bevel(mesh('Propeller blade',verts,faces,M_PROP),.009);blade.parent=prop
    # Thin yellow cap, both faces.
    for d in [-.024,.024]:
        points=[]
        for tangent,r in [(.12,1.37),(.04,1.49),(-.06,1.48),(-.11,1.37)]:
            points.append((tangent*cos(a)+r*sin(a),d+tangent*.16,r*cos(a)-tangent*sin(a)))
        cap=mesh('Propeller yellow tip',points,[(0,1,2,3)],M_YELLOW);cap.parent=prop
bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,location=(0,-3.79,0))
spinner=move(bpy.context.object);spinner.name='Pointed aluminum spinner';spinner.scale=(.245,.39,.245);spinner.data.materials.append(M_SPINNER)
bpy.context.view_layer.update()
for polygon in spinner.data.polygons:polygon.use_smooth=True
matrix=spinner.matrix_world.copy();spinner.parent=prop;spinner.matrix_world=matrix

for sign in [-1,1]:
    cylinder('Cowling gun port',.032,.16,(sign*.22,-3.46,.43),M_DARK,8)
    for y in [-2.65,-2.46]:
        ob=cylinder('Exhaust outlet',.062,.13,(sign*.54,y,-.26),M_STEEL,8);ob.rotation_euler=(0,pi/2,0)
    # Closed gear door perimeter conforms to the underside airfoil.
    xy=[(.80,-1.48),(1.08,-1.49),(1.55,-.72),(1.53,-.33),(1.20,-.23),(.92,-.53),(.8,-1.48)]
    tube('Retracted gear door',[(sign*x,y,wing_z(sign*x,y,True)-.005) for x,y in xy],.006,M_SEAM)

# Ivory band conforming to the tapering rear fuselage.
verts=[]
for y in [2.13,2.39]:
    rx,rz,zc=body_radius(y)
    for j in range(33):
        angle=2*pi*j/32
        verts.append(((rx+.008)*sin(angle),y,zc+(rz+.008)*cos(angle)))
mesh('Ivory tail band',verts,[(j,j+1,j+34,j+33) for j in range(32)],M_IVORY,smooth=True)
M_TAIL=material('Burgundy unit stripe',(.20,.014,.018),.48)
for side in [-1,1]:
    mesh('Diagonal fin stripe',[(side*.048,2.72,.70),(side*.048,2.82,.94),(side*.048,3.50,1.48),(side*.048,3.55,1.22)],[(0,1,2,3)],M_TAIL)
tube('Antenna wire',[(0,1.20,1.04),(0,3.19,1.70)],.004,M_DARK)
# A longer, more slender airframe than the Zero; preserve assemblies and UVs.
for ob in air.objects:
    if ob.type=='MESH':
        for vertex in ob.data.vertices: vertex.co.y *= 1.07
    elif ob.type=='CURVE':
        for spline in ob.data.splines:
            for point in spline.points: point.co.y *= 1.07
    ob.location.y *= 1.07

for ob in air.objects:
    if ob.type=='MESH':
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()

# Pack concept and real local HDR. Neutral background is visible only to camera.
ref=bpy.data.objects.new('Hayabusa three-view reference',None);refs.objects.link(ref)
ref.empty_display_type='IMAGE';ref.data=bpy.data.images.load(str(ART/'hayabusa-reference-v01.png'));ref.empty_display_size=12
ref.location=(15,0,0);ref.hide_render=True;refs.hide_viewport=True
world=bpy.data.worlds.new('Studio HDR 4K');scene.world=world;world.use_nodes=True
n=world.node_tree.nodes;n.clear();l=world.node_tree.links
env=n.new('ShaderNodeTexEnvironment');env.image=bpy.data.images.load(str(ROOT/'blender/studio_small_07_4k.exr'))
bg=n.new('ShaderNodeBackground');bg.inputs['Strength'].default_value=.45;l.new(env.outputs['Color'],bg.inputs['Color'])
flat=n.new('ShaderNodeBackground');flat.inputs['Color'].default_value=(.72,.69,.63,1);flat.inputs['Strength'].default_value=1
path=n.new('ShaderNodeLightPath');mix=n.new('ShaderNodeMixShader');out=n.new('ShaderNodeOutputWorld')
l.new(path.outputs['Is Camera Ray'],mix.inputs[0]);l.new(bg.outputs[0],mix.inputs[1]);l.new(flat.outputs[0],mix.inputs[2]);l.new(mix.outputs[0],out.inputs[0])
for name,loc,power,size,color in [('Key',(-4,-6,8),1300,7,(1,.93,.83)),('Fill',(5,-2,5),950,6,(.80,.89,1)),('Rim',(1,6,7),1300,5,(1,.98,.92)),('Under',(-2,-4,-7),1100,7,(.90,.95,1))]:
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=color
    ob=bpy.data.objects.new(name,d);studio.objects.link(ob);ob.location=loc;ob.rotation_euler=(-ob.location).to_track_quat('-Z','Y').to_euler()

cams=[]
for name,loc,rot,scale in [('01 DESSUS',(0,0,22),(0,0,pi),13.0),('02 DESSOUS',(0,0,-22),(pi,0,0),13.0),('03 TROIS QUARTS',(10,-15,9),None,13.2)]:
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
scene.camera=cams[2];scene['asset_notes']='Hayabusa-inspired stylized low-poly enemy; generated paint texture + authored geometry and insignia. Nose -Y.'
for img in bpy.data.images:
    if img.source=='FILE':img.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'hayabusa-studio.blend'))
stats={'base_triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in air.objects if o.type=='MESH'),
       'mesh_objects':sum(o.type=='MESH' for o in air.objects),'render_engine':'Cycles','samples':scene.cycles.samples,'resolution':scene.render.resolution_x}
(OUT/'build-report.json').write_text(json.dumps(stats,indent=2))
for cam,name in zip(cams,['01-dessus','02-dessous','03-trois-quarts']):
    scene.camera=cam;scene.render.filepath=str(RENDERS/(name+('-preview' if PREVIEW else '')+'.png'));bpy.ops.render.render(write_still=True)
scene.camera=cams[2];bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'hayabusa-studio.blend'))
print('HAYABUSA COMPLETE',stats)
