import bpy, json, os
root='C:/ChatGPT/1942'
assert len([o for o in bpy.data.objects if o.type=='CAMERA']) == 3
file_images=[i for i in bpy.data.images if i.source=='FILE']
assert len(file_images)>=4
assert all(i.packed_file for i in file_images), 'Unpacked external image'
for filename in ['01-dessus.png','02-dessous.png','03-trois-quarts.png']:
    path=root+'/renders/'+filename
    assert os.path.getsize(path)>100000
    image=bpy.data.images.load(path,check_existing=False)
    assert tuple(image.size)==(2200,2200)
report={'blend_reopened':True,'cameras':3,'packed_images':[i.name for i in file_images],
        'render_dimensions':[2200,2200],'renders_verified':3,
        'engine':bpy.context.scene.render.engine}
with open(root+'/blender/verification.json','w') as f:json.dump(report,f,indent=2)
print('VERIFIED',json.dumps(report))
