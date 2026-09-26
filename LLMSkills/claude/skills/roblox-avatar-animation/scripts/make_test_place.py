"""Write a small sandbox Place (.rbxlx) for testing a pose layer on a clean avatar, away from any game code.

  python scripts/make_test_place.py OUT.rbxlx [--layer PATH.luau] [--kit PATH.luau]

Contents: a Baseplate, a 20-stud slope (about 22 degrees), a staircase (1-stud rises), a SpawnLocation, and under
StarterPlayer/StarterPlayerScripts/Anim: ModuleScripts AvatarPoseKit + PoseLayer and a LocalScript "Boot" that calls
PoseLayer.trackAll() and toggles the layer with the LocalPlayer attribute "PoseLayerOff" (for A/B measurements).
The default Roblox Animate script drives the avatar, so this measures what the layer adds on top of stock animations.
Open it in its own Studio: RobloxStudioBeta.exe -task EditFile -localPlaceFile "<full path>".
"""
import argparse
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILL = HERE.parent
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


BOOT = """local Players = game:GetService("Players")
local Layer = require(script.Parent:WaitForChild("PoseLayer"))
Layer.trackAll()
local lp = Players.LocalPlayer
lp:GetAttributeChangedSignal("PoseLayerOff"):Connect(function()
	Layer.setEnabled(lp:GetAttribute("PoseLayerOff") ~= true)
end)
-- live tuning from the command bar / MCP: set a LocalPlayer attribute "Layer_<FIELD>" (e.g. Layer_FLOOR_RATE = 30,
-- Layer_CORRECTION_RATE_DEG = 1440) and the running layer picks it up
lp.AttributeChanged:Connect(function(name)
	local field = name:match("^Layer_(.+)$")
	if not field then return end
	local value = lp:GetAttribute(name)
	if field:match("_DEG$") then
		Layer[field:gsub("_DEG$", "")] = math.rad(value)
	else
		Layer[field] = value
	end
end)
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--layer", default=str(SKILL / "assets/PoseLayerTemplate.luau"))
    ap.add_argument("--kit", default=str(SKILL / "assets/AvatarPoseKit.luau"))
    a = ap.parse_args()
    kit = Path(a.kit).read_text(encoding="utf-8")
    layer = Path(a.layer).read_text(encoding="utf-8")
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
    anim = script("ModuleScript", "AvatarPoseKit", kit) + script("ModuleScript", "PoseLayer", layer) + script("LocalScript", "Boot", BOOT)
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        f'<Item class="Workspace" referent="{ref()}"><Properties><string name="Name">Workspace</string></Properties>{world}</Item>'
        f'<Item class="StarterPlayer" referent="{ref()}"><Properties><string name="Name">StarterPlayer</string></Properties>'
        f'<Item class="StarterPlayerScripts" referent="{ref()}"><Properties><string name="Name">StarterPlayerScripts</string></Properties>'
        f'<Item class="Folder" referent="{ref()}"><Properties><string name="Name">Anim</string></Properties>{anim}</Item>'
        '</Item></Item></roblox>'
    )
    Path(a.out).write_text(xml, encoding="utf-8")
    print("wrote", a.out, len(xml), "bytes")


if __name__ == "__main__":
    main()
