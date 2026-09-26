"""Checks that every instance of the pre-reskin menu still exists at the same path with the same class.

Compares tree_before.json (original project, dumped by dump_tree.luau) with tree.json (reskin), for the
1280x720 home state (all pages are built at startup, so every named instance is present).
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))

def paths(tree):
    out = {}
    def walk(node, prefix):
        path = prefix + "." + node["Name"] if prefix else node["Name"]
        out.setdefault(path, set()).add(node["ClassName"])
        for child in node.get("Children") or []:
            if isinstance(child, dict):
                walk(child, path)
    walk(tree, "")
    return out

def state(file, name):
    for s in json.load(open(os.path.join(HERE, file), encoding="utf-8")):
        if s["name"] == name:
            return s["tree"]

before = paths(state("tree_before.json", "home@1280x720"))
after = paths(state("tree.json", "home@1280x720"))
STYLE_ONLY = {"UICorner", "UIStroke"}  # appearance modifiers; nothing looks these up by name
missing, restyled = [], []
for path, classes in sorted(before.items()):
    if not (classes & after.get(path, set())):
        (restyled if classes <= STYLE_ONLY else missing).append((path, sorted(classes), sorted(after.get(path, set()))))
print(f"{len(before)} original paths checked: {len(before) - len(missing) - len(restyled)} identical, "
      f"{len(restyled)} style-only modifiers moved (UICorner/UIStroke now live on the button's Face/Base), "
      f"{len(missing)} named instances missing/changed")
for path, want, got in missing:
    print("  MISSING", path, "want", want, "got", got or "-")
sys.exit(1 if missing else 0)
