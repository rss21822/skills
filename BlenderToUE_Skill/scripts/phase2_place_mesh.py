# Phase2: メッシュ配置（UE Execute Python Script）
# 焼き込み判定 → 原点配置（焼き込み時）
import unreal

# ===== CONFIG =====
SM_FOLDER = '/Game/YourProject/StaticMesh'
LABEL = 'ABS_'
BAKE_THRESHOLD = 1000.0
# ==================

es = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
assets = unreal.EditorAssetLibrary.list_assets(SM_FOLDER, recursive=True, include_folder=False)
sms = []
for p in assets:
    o = unreal.load_asset(p)
    if isinstance(o, unreal.StaticMesh): sms.append(o)

mags = []
for o in sms[:20]:
    b = o.get_bounds().origin
    mags.append((abs(b.x)+abs(b.y)+abs(b.z))/3.0)
avg = (sum(mags)/len(mags)) if mags else 0.0
baked = avg > BAKE_THRESHOLD

if not sms:
    print('No StaticMesh. Check SM_FOLDER:', SM_FOLDER)
elif not baked:
    print('NOT baked (avg origin=%.1f) = local space. Need transform placement.' % avg)
else:
    for a in es.get_all_level_actors():
        if a.get_actor_label().startswith(LABEL): es.destroy_actor(a)
    cnt = 0
    for o in sms:
        a = es.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(0,0,0), unreal.Rotator(0,0,0))
        a.static_mesh_component.set_static_mesh(o)
        a.set_actor_label(LABEL + o.get_name())
        cnt += 1
    print('BAKED (avg=%.1f). placed %d StaticMeshActors at origin.' % (avg, cnt))
