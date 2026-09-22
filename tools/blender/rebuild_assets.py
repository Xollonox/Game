import bpy, math, os
from mathutils import Vector, Matrix
ROOT=os.environ.get('GAME_ROOT', os.getcwd()); OUT=os.environ.get('ASSET_OUT', os.path.join(ROOT,'assets/generated')); os.makedirs(OUT,exist_ok=True)

def fresh(): bpy.ops.wm.read_factory_settings(use_empty=True)

def sword(num):
 fresh(); src=f'{ROOT}/assets/models/weapons/swords_pack/fbx/sword_{num}.fbx'; bpy.ops.import_scene.fbx(filepath=src)
 for o in list(bpy.data.objects):
  if o.type in {'CAMERA','LIGHT'}: bpy.data.objects.remove(o,do_unlink=True)
 ob=next(o for o in bpy.data.objects if o.type=='MESH'); pts=[ob.matrix_world@v.co for v in ob.data.vertices]; xs=[p.x for p in pts]; lo,hi=min(xs),max(xs); step=(hi-lo)/40; guard=None
 for i in range(40):
  a=hi-(i+1)*step; b=hi-i*step; q=[p for p in pts if a<=p.x<=b]
  if q and max(p.z for p in q)-min(p.z for p in q)>0.4: guard=a; break
 guard=guard if guard is not None else hi-1.2; grip=(hi+guard)/2
 ob.matrix_world=Matrix.Diagonal((.1,.1,.1,1))@Matrix.Rotation(math.radians(-90),4,'Z')@Matrix.Translation(Vector((-grip,0,0)))@ob.matrix_world
 bpy.context.view_layer.update(); bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob; bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 for o in list(bpy.data.objects):
  if o is not ob: bpy.data.objects.remove(o,do_unlink=True)
 dst=f'{OUT}/sword_{num}.glb'; bpy.ops.export_scene.gltf(filepath=dst,export_format='GLB'); print('SWORD',num,dst)
for n in (1,3,8): sword(n)

fresh(); bpy.ops.import_scene.gltf(filepath=f'{ROOT}/assets/models/characters/quaternius_universal/universal_character.glb')
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE'); body=bpy.data.objects['Mannequin']; k=body.dimensions.z/1.75; bones=arm.data.bones
def pos(n,f=.5): return bones[n].head_local.lerp(bones[n].tail_local,f)
def mat(n,c,metal,rough):
 m=bpy.data.materials.new(n); m.use_nodes=True; p=m.node_tree.nodes['Principled BSDF']; p.inputs['Base Color'].default_value=(*c,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough; return m
steel=mat('M_ArmorSteel',(.55,.58,.64),.85,.38); leather=mat('M_ArmorLeather',(.13,.10,.08),0,.8); pieces=[]
def sph(n,loc,scale,ma):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=18,ring_count=10,radius=1,location=loc); o=bpy.context.object;o.name=n;o.scale=scale;o.data.materials.append(ma);bpy.ops.object.shade_smooth();return o
def cube(n,loc,scale,ma):
 bpy.ops.mesh.primitive_cube_add(size=2,location=loc);o=bpy.context.object;o.name=n;o.scale=scale;o.data.materials.append(ma);return o
h=pos('DEF-head'); pieces += [(sph('Helmet',h+Vector((0,0,.012*k)),(.108*k,.115*k,.118*k),steel),'DEF-head'),(cube('Visor',h+Vector((0,-.105*k,-.018*k)),(.078*k,.02*k,.03*k),leather),'DEF-head'),(cube('Crest',h+Vector((0,0,.128*k)),(.012*k,.09*k,.035*k),leather),'DEF-head')]
for s in ('L','R'): pieces.append((sph('Pauldron.'+s,pos('DEF-upper_arm.'+s,.1)+Vector((0,0,.02*k)),(.088*k,.088*k,.072*k),steel),'DEF-upper_arm.'+s))
pieces += [(cube('ChestPlate',pos('DEF-spine.003',.38)+Vector((0,-.015*k,0)),(.155*k,.098*k,.145*k),steel),'DEF-spine.003'),(cube('Belt',pos('DEF-hips',.45)+Vector((0,0,.02*k)),(.165*k,.12*k,.042*k),leather),'DEF-hips')]
for s in ('L','R'): pieces.append((cube('Tasset.'+s,pos('DEF-thigh.'+s,.15)+Vector((0,0,.06*k)),(.075*k,.075*k,.075*k),leather),'DEF-thigh.'+s))
for o,b in pieces:
 vg=o.vertex_groups.new(name=b);vg.add(range(len(o.data.vertices)),1,'REPLACE');mod=o.modifiers.new('Armature','ARMATURE');mod.object=arm
bpy.ops.object.select_all(action='DESELECT')
for o,_ in pieces:o.select_set(True)
body.select_set(True);bpy.context.view_layer.objects.active=body;bpy.ops.object.join();bpy.ops.export_scene.gltf(filepath=f'{OUT}/universal_character_armored.glb',export_format='GLB',export_animations=True,export_animation_mode='ACTIONS');print('ARMOR_DONE')
