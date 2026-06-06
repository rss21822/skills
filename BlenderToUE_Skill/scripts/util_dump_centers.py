# util: メッシュ中心ダンプ（座標フィットがズレる時の厳密照合用）
import unreal, json
es = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
LABEL = 'ABS_'
OUT = r'E:\export\ue_centers.json'
rows = []
for a in es.get_all_level_actors():
    l = a.get_actor_label()
    if l.startswith(LABEL):
        org, ext = a.get_actor_bounds(False)
        rows.append({'n': l[len(LABEL):], 'c': [round(org.x,2), round(org.y,2), round(org.z,2)]})
with open(OUT, 'w', encoding='utf-8') as f:
    json.dump(rows, f, ensure_ascii=False)
print('dumped', len(rows), '->', OUT)
