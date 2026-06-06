# Phase0: Blender下準備（Blender MCP / bpyで実行）
# テクスチャ2K化 → unpack → ライト書き出し → FBXエクスポート
import bpy, os, math, json
from mathutils import Vector

# ===== CONFIG =====
TEX_MAX = 2048
LIGHTS_OUT = r'E:\export\lights.json'
FBX_OUT    = r'E:\export\scene.fbx'
DO_FBX_EXPORT = True
# ==================

os.makedirs(os.path.dirname(LIGHTS_OUT), exist_ok=True)

# 1) テクスチャ2K化
tex_changed = 0
for img in bpy.data.images:
    if img.type != 'IMAGE': continue
    w, h = img.size[0], img.size[1]
    if w == 0 or h == 0: continue
    m = max(w, h)
    if m > TEX_MAX:
        sc = TEX_MAX / m
        img.scale(max(1, int(round(w*sc))), max(1, int(round(h*sc))))
        if img.packed_file: img.pack()
        tex_changed += 1

# 2) unpack（外部PNG化：FBXにテクスチャを乗せるため）
try:
    bpy.ops.file.unpack_all(method='WRITE_LOCAL')
except Exception as e:
    print('unpack warn:', e)

# 3) ライト書き出し（UE座標 (x,-y,z)*100）
points, spots, others = [], [], []
for o in bpy.context.scene.objects:
    if o.type != 'LIGHT': continue
    ld = o.data; mw = o.matrix_world; loc = mw.translation
    ue_loc = [round(loc.x*100,2), round(-loc.y*100,2), round(loc.z*100,2)]
    col = [round(ld.color[0],4), round(ld.color[1],4), round(ld.color[2],4)]
    e = round(ld.energy, 2)
    if ld.type == 'POINT':
        points.append({'loc':ue_loc,'c':col,'e':e})
    elif ld.type == 'SPOT':
        d = (mw.to_3x3() @ Vector((0,0,-1))).normalized()
        spots.append({'loc':ue_loc,'c':col,'e':e,'ang':round(math.degrees(ld.spot_size),3),
                      'dir':[round(d.x,5),round(-d.y,5),round(d.z,5)]})
    else:
        others.append({'type':ld.type,'loc':ue_loc,'c':col,'e':e})
with open(LIGHTS_OUT, 'w', encoding='utf-8') as f:
    json.dump({'points':points,'spots':spots,'others':others}, f, ensure_ascii=False)

# 4) FBXエクスポート（Path Mode=Copy）
if DO_FBX_EXPORT:
    os.makedirs(os.path.dirname(FBX_OUT), exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=FBX_OUT, path_mode='COPY', embed_textures=False,
                             object_types={'MESH'}, apply_unit_scale=True)

result = {'tex_resized':tex_changed, 'n_points':len(points), 'n_spots':len(spots), 'fbx':FBX_OUT}
