# Phase3: 発光マテリアル（UE Execute Python Script）
# メッシュが参照するマテリアルを辿り、Emission系のEmissiveColorを上書き
import unreal

# ===== CONFIG =====
SM_FOLDER = '/Game/YourProject/StaticMesh'
EMIS_NAME_HINT = 'emiss'   # 発光マテリアル名に含まれる語（小文字）
WARM = (1.0, 0.405, 0.231)
EMI = 100.0
# ==================

mel = unreal.MaterialEditingLibrary
col = unreal.LinearColor(WARM[0]*EMI, WARM[1]*EMI, WARM[2]*EMI, 1.0)

mats = {}
for p in unreal.EditorAssetLibrary.list_assets(SM_FOLDER, recursive=True, include_folder=False):
    o = unreal.load_asset(p)
    if isinstance(o, unreal.StaticMesh):
        for sm in o.get_editor_property('static_materials'):
            mi = sm.get_editor_property('material_interface')
            if mi: mats[mi.get_path_name()] = mi

allnames = sorted(set(m.get_name() for m in mats.values()))
applied = []
for mi in mats.values():
    nm = mi.get_name()
    if EMIS_NAME_HINT not in nm.lower(): continue
    try:
        if isinstance(mi, unreal.MaterialInstanceConstant):
            parent = mi.get_editor_property('parent'); base = parent if parent else mi
            vparams = [str(x) for x in mel.get_vector_parameter_names(base)]
            ev = next((x for x in vparams if 'emiss' in x.lower()), None)
            if ev:
                mel.set_material_instance_vector_parameter_value(mi, ev, col)
                unreal.EditorAssetLibrary.save_loaded_asset(mi)
                applied.append(nm+' : '+ev)
            else:
                applied.append(nm+' : NO_PARAM '+str(vparams))
        elif isinstance(mi, unreal.Material):
            node = mel.create_material_expression(mi, unreal.MaterialExpressionConstant3Vector, -400, 0)
            node.set_editor_property('constant', col)
            mel.connect_material_property(node, '', unreal.MaterialProperty.MP_EMISSIVE_COLOR)
            mel.recompile_material(mi)
            unreal.EditorAssetLibrary.save_loaded_asset(mi)
            applied.append(nm+' : base')
    except Exception as e:
        applied.append(nm+' : ERR '+str(e))

print('ALL_MATS:', allnames)
print('APPLIED:', applied)
# 発光面がUEで欠落しスロットがWorldGridMaterial/空に化けた場合は、
# 対象アセットのそのスロットを発光ベースマテリアルに差し替える（fix版を別途使用）。
