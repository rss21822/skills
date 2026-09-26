"""Sandbox Place (.rbxlx) for the TerrainPose layer: Baseplate, a 22 deg slope, a 1-stud staircase, and
StarterPlayerScripts/TerrainPose (AvatarPoseKit + TerrainPoseCore + TerrainPoseLayer + Boot) on the default Animate.
Adapted from roblox-avatar-animation/scripts/make_test_place.py.

  python tools/make_sandbox.py OUT.rbxlx          (run from the outputs folder)

Map: Slope at x=40 (rises toward +Z from z=5 to z=55), staircase at x=-40 (Step0..Step7, 1-stud rises, 3-stud treads,
from z=20), SpawnLocation at the origin. A/B with the LocalPlayer attribute "TerrainPoseOff".
Open it in its own Studio: RobloxStudioBeta.exe -task EditFile -localPlaceFile "<full path>".
"""
import argparse
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parent / "src" / "client" / "TerrainPose"
_ref = [0]


def ref():
    _ref[0] += 1
    return f"RBX{_ref[0]:06d}"


def cframe(x, y, z, rot=(1, 0, 0, 0, 1, 0, 0, 0, 1)):
    names = ["R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    body = "".join(f"<{n}>{v}</{n}>" for n, v in zip(names, rot))
    return f'<CoordinateFrame name="CFrame"><X>{x}</X><Y>{y}</Y><Z>{z}</Z>{body}</CoordinateFrame>'


def part(cls, name, size, pos, color=(163, 162, 165), rot=(1, 0, 0, 0, 1, 0, 0, 0, 1)):
    r, g, b = color
    c3 = (255 << 24) | (r << 16) | (g << 8) | b
    return (f'<Item class="{cls}" referent="{ref()}"><Properties><string name="Name">{name}</string>'
            f'<bool name="Anchored">true</bool>{cframe(*pos, rot=rot)}'
            f'<Vector3 name="size"><X>{size[0]}</X><Y>{size[1]}</Y><Z>{size[2]}</Z></Vector3>'
            f'<Color3uint8 name="Color3uint8">{c3}</Color3uint8></Properties></Item>')


def script(cls, name, source, children=""):
    source = source.replace("]]>", "]]]]><![CDATA[>")
    return (f'<Item class="{cls}" referent="{ref()}"><Properties><string name="Name">{name}</string>'
            f'<ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString></Properties>{children}</Item>')




def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    a = ap.parse_args()
    read = lambda name: (SRC / name).read_text(encoding="utf-8")
    world = "".join([
        part("Part", "Baseplate", (512, 20, 512), (0, -10, 0), (91, 154, 76)),
        part("SpawnLocation", "SpawnLocation", (6, 1, 6), (0, 0.5, 0)),
        # slope: wedge rising toward +Z, 20 tall over 50 long (about 22 degrees)
        part("WedgePart", "Slope", (16, 20, 50), (40, 10, 30), (200, 190, 150)),
        part("Part", "SlopeTop", (16, 20, 20), (40, 10, 65), (200, 190, 150)),
    ] + [
        part("Part", f"Step{i}", (12, 1 + i, 3), (-40, (1 + i) / 2, 20 + 3 * i), (170, 170, 190)) for i in range(8)
    ] + [
        part("Part", "StairTop", (12, 8, 12), (-40, 4, 48.5), (170, 170, 190)),
    ])
    anim = (script("ModuleScript", "AvatarPoseKit", read("AvatarPoseKit.luau"))
            + script("ModuleScript", "TerrainPoseCore", read("TerrainPoseCore.luau"))
            + script("ModuleScript", "TerrainPoseLayer", read("TerrainPoseLayer.luau"))
            + script("LocalScript", "Boot", read("Boot.client.luau")))
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        f'<Item class="Workspace" referent="{ref()}"><Properties><string name="Name">Workspace</string></Properties>{world}</Item>'
        f'<Item class="StarterPlayer" referent="{ref()}"><Properties><string name="Name">StarterPlayer</string></Properties>'
        f'<Item class="StarterPlayerScripts" referent="{ref()}"><Properties><string name="Name">StarterPlayerScripts</string></Properties>'
        f'<Item class="Folder" referent="{ref()}"><Properties><string name="Name">TerrainPose</string></Properties>{anim}</Item>'
        '</Item></Item></roblox>'
    )
    Path(a.out).write_text(xml, encoding="utf-8")
    print("wrote", a.out, len(xml), "bytes")


if __name__ == "__main__":
    main()
