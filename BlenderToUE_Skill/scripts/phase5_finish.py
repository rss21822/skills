# Phase5: 仕上げ（UE Execute Python Script）
# PostProcess: Lumen + Bloom + 露出bias（ロックしない）＋ 薄い暖色フォグ
import unreal

# ===== CONFIG =====
PPV_LABEL = 'PPV_FINISH'
FOG_LABEL = 'HeightFog_FINISH'
BLOOM = 1.5
EXPOSURE_BIAS = 0.0
FOG_DENSITY = 0.008
FOG_COLOR = (1.0, 0.55, 0.3)
# ==================

es = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

for a in es.get_all_level_actors():
    if a.get_actor_label() == PPV_LABEL: es.destroy_actor(a)
ppv = es.spawn_actor_from_class(unreal.PostProcessVolume, unreal.Vector(0,0,0), unreal.Rotator(0,0,0))
ppv.set_actor_label(PPV_LABEL)
ppv.set_editor_property('unbound', True)
s = ppv.get_editor_property('settings')
s.set_editor_property('override_dynamic_global_illumination_method', True)
s.set_editor_property('dynamic_global_illumination_method', unreal.DynamicGlobalIlluminationMethod.LUMEN)
s.set_editor_property('override_reflection_method', True)
s.set_editor_property('reflection_method', unreal.ReflectionMethod.LUMEN)
s.set_editor_property('override_bloom_intensity', True)
s.set_editor_property('bloom_intensity', BLOOM)
s.set_editor_property('override_auto_exposure_bias', True)
s.set_editor_property('auto_exposure_bias', EXPOSURE_BIAS)
ppv.set_editor_property('settings', s)

for a in es.get_all_level_actors():
    if a.get_actor_label() == FOG_LABEL: es.destroy_actor(a)
fog_msg = 'ok'
try:
    fog = es.spawn_actor_from_class(unreal.ExponentialHeightFog, unreal.Vector(0,0,0), unreal.Rotator(0,0,0))
    fog.set_actor_label(FOG_LABEL)
    comp = None
    for attr in ['exponential_height_fog_component', 'component']:
        try:
            comp = getattr(fog, attr)
            if comp: break
        except Exception: pass
    if comp is None: comp = fog.get_editor_property('component')
    comp.set_editor_property('fog_density', FOG_DENSITY)
    comp.set_editor_property('fog_inscattering_color', unreal.LinearColor(FOG_COLOR[0], FOG_COLOR[1], FOG_COLOR[2], 1.0))
    comp.set_editor_property('volumetric_fog', False)
except Exception as e:
    fog_msg = 'fog_err: ' + str(e)

print('PPV set (Lumen+Bloom+exposure bias). fog:', fog_msg)
# 空は黒のまま（Blenderが黒ワールドなら SkyLight/SkyAtmosphere を追加しない）
