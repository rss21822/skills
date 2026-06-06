# Phase4: ライト配置（UE Execute Python Script）
# メッシュ実バウンズにライト座標をフィット（S,O）＋間引き＋影OFF
import unreal, json

# ===== CONFIG =====
LIGHTS_JSON = r'E:\export\lights.json'
SM_LABEL = 'ABS_'        # Phase2で付けた接頭辞
PT_LABEL = 'PT_'
SP_LABEL = 'SP_'
POINT_STEP = 12
POINT_INTENSITY = 30000.0
POINT_RADIUS = 1500.0
SPOT_INTENSITY = 2000000.0
SPOT_RADIUS = 8000.0
TEST = True
TEST_POINTS = 150
# ==================

es = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
with open(LIGHTS_JSON, encoding='utf-8') as f:
    d = json.load(f)

centers = []
for a in es.get_all_level_actors():
    if a.get_actor_label().startswith(SM_LABEL):
        org, ext = a.get_actor_bounds(False)
        centers.append((org.x, org.y, org.z))

def pct(vals, p):
    s = sorted(vals); i = max(0, min(len(s)-1, int(len(s)*p))); return s[i]

mmin = [pct([c[k] for c in centers], 0.05) for k in range(3)]
mmax = [pct([c[k] for c in centers], 0.95) for k in range(3)]
mesh_c = [(mmin[k]+mmax[k])/2 for k in range(3)]
mesh_size = max(mmax[k]-mmin[k] for k in range(3))

pts = d['points']
lmin = [min(p['loc'][k] for p in pts) for k in range(3)]
lmax = [max(p['loc'][k] for p in pts) for k in range(3)]
light_c = [(lmin[k]+lmax[k])/2 for k in range(3)]
light_size = max(lmax[k]-lmin[k] for k in range(3))

S = mesh_size/light_size if light_size else 1.0
O = [mesh_c[k]-light_c[k]*S for k in range(3)]
def conv(loc):
    return unreal.Vector(loc[0]*S+O[0], loc[1]*S+O[1], loc[2]*S+O[2])

for a in es.get_all_level_actors():
    l = a.get_actor_label()
    if l.startswith(PT_LABEL) or l.startswith(SP_LABEL) or l == 'TESTLIGHT':
        es.destroy_actor(a)

ns = 0
for i, s in enumerate(d['spots']):
    rot = unreal.MathLibrary.make_rot_from_x(unreal.Vector(s['dir'][0], s['dir'][1], s['dir'][2]))
    a = es.spawn_actor_from_class(unreal.SpotLight, conv(s['loc']), rot)
    a.set_actor_label(SP_LABEL + str(i))
    c = a.spot_light_component
    c.set_mobility(unreal.ComponentMobility.MOVABLE)
    c.set_intensity(SPOT_INTENSITY)
    c.set_light_color(unreal.LinearColor(s['c'][0], s['c'][1], s['c'][2], 1.0))
    c.set_attenuation_radius(SPOT_RADIUS*S)
    c.set_editor_property('outer_cone_angle', s['ang']/2.0)
    c.set_editor_property('inner_cone_angle', max(0.0, s['ang']/2.0-5.0))
    ns += 1

npl = 0
lim = TEST_POINTS if TEST else 10**9
for i in range(0, len(pts), POINT_STEP):
    if npl >= lim: break
    p = pts[i]
    a = es.spawn_actor_from_class(unreal.PointLight, conv(p['loc']), unreal.Rotator(0,0,0))
    a.set_actor_label(PT_LABEL + str(i))
    c = a.point_light_component
    c.set_mobility(unreal.ComponentMobility.MOVABLE)
    c.set_intensity(POINT_INTENSITY)
    c.set_light_color(unreal.LinearColor(p['c'][0], p['c'][1], p['c'][2], 1.0))
    c.set_attenuation_radius(POINT_RADIUS*S)
    c.set_editor_property('cast_shadows', False)
    npl += 1

print('S=', round(S,3), 'O=', [round(x) for x in O], 'spots:', ns, 'points:', npl, ('TEST' if TEST else 'FULL'))
