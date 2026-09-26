"""Objective grading for roblox-avatar-animation iteration runs.

  python grade.py iteration-1            -> writes <run>/grading.json for every eval-*/<config>/ and prints a summary

Programmatic checks only (grep / parse / compile / run the run's own tests with Lune). Judgment items are added by
hand into grading.json afterwards (same fields: text, passed, evidence).
"""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LUNE = Path.home() / ".rokit/tool-storage/lune-org/lune/0.10.5/lune.exe"
ORIGINAL_GAME = Path.home() / ".claude/skills/roblox-avatar-animation/evals/files/mini-game/places/Game.rbxlx"

COMPILE = '''local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local bad = 0
for _, p in process.args do
	local ok, err = pcall(luau.compile, fs.readFile(p))
	if not ok then bad += 1; print("FAIL " .. p .. " " .. tostring(err)) end
end
print("compiled " .. #process.args .. " bad " .. bad)
'''


def luau_files(root, exclude_tests=False):
    out = []
    for p in root.rglob("*.luau"):
        if ".git" in p.parts:
            continue
        if exclude_tests and ("tests" in p.parts or p.name.startswith("test")):
            continue
        out.append(p)
    return out


def read(p):
    try:
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def strip_comments(src):
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    return re.sub(r"--[^\n]*", "", src)


def compile_all(files, cwd):
    if not files:
        return False, "no .luau files"
    tmp = cwd / "_compile_check.luau"
    tmp.write_text(COMPILE, encoding="utf-8")
    try:
        proc = subprocess.run([str(LUNE), "run", str(tmp)] + [str(f) for f in files], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=120)
    finally:
        tmp.unlink(missing_ok=True)
    text = (proc.stdout + proc.stderr).strip()
    ok = proc.returncode == 0 and re.search(r"bad 0\b", text) is not None
    return ok, text[-400:]


def run_tests(outputs):
    tests = [p for p in outputs.rglob("*.luau") if ".git" not in p.parts and ("tests" in p.parts or p.name.startswith("test"))
             and "studio" not in p.parts and not p.name.endswith((".client.luau", ".server.luau"))
             and not p.name.startswith(("compile", "_"))]
    if not tests:
        return False, "no test files"
    results = []
    ok = True
    for t in tests:
        # run from the directory that makes the test's relative paths work: try the test's repo root candidates
        passed, last = False, ""
        for cwd in [outputs / "mini-game", outputs, t.parent, t.parent.parent]:
            if not cwd.exists():
                continue
            try:
                proc = subprocess.run([str(LUNE), "run", str(t)], cwd=cwd, capture_output=True, text=True,
                                      encoding="utf-8", errors="replace", timeout=300)
            except subprocess.TimeoutExpired:
                last = "timeout"
                continue
            out = (proc.stdout + proc.stderr).strip()
            last = out.splitlines()[-1] if out else f"exit {proc.returncode}"
            if proc.returncode == 0 and not re.search(r"\bFAIL", out):
                passed = True
                break
        ok &= passed
        results.append(f"{t.name}: {'PASS' if passed else 'FAIL'} ({last[:120]})")
    return ok, "; ".join(results)


def transform_timing(files):
    writers, bad = [], []
    for f in files:
        src = strip_comments(read(f))
        if re.search(r"\.Transform\s*=[^=]", src):
            writers.append(f.name)
            if re.search(r"RenderStepped|PreRender|BindToRenderStep", src):
                bad.append(f.name)
            elif not re.search(r"PreSimulation|\.Stepped", src):
                # module that writes Transform when called: accept if some other file drives it from PreSimulation
                pass
    driver = any(re.search(r"PreSimulation|\.Stepped", strip_comments(read(f))) for f in files)
    if not writers:
        return None, "no Transform writes"
    return (not bad and driver), f"writers={writers} renderstep_writers={bad} presim_driver={driver}"


def physics_writes(files):
    hits = []
    for f in files:
        src = strip_comments(read(f))
        for pat in [r"RootPart\.CFrame\s*=[^=]", r"\.AssemblyLinearVelocity\s*=[^=]", r"HipHeight\s*=[^=]",
                    r"\.Anchored\s*=\s*true", r"WalkSpeed\s*=[^=]", r"RootPart\.Position\s*=[^=]"]:
            for m in re.finditer(pat, src):
                hits.append(f"{f.name}:{pat}")
    return not hits, (", ".join(hits) or "none")


def grade_run(run, eval_name):
    outputs = run / "outputs"
    exp = []

    def add(text, passed, evidence):
        exp.append({"text": text, "passed": bool(passed), "evidence": evidence})

    all_luau = luau_files(outputs)
    src = luau_files(outputs, exclude_tests=True)
    report = read(outputs / "REPORT.md")
    ok, ev = compile_all(all_luau, outputs)
    add("All Luau files compile", ok, ev)
    ok, ev = run_tests(outputs)
    add("The run's own offline tests run under Lune and pass", ok, ev)
    code = "\n".join(strip_comments(read(f)) for f in src)
    add("Finds AnimationConstraint joints too (Server Authority avatars have no Motor6D)",
        "AnimationConstraint" in code, "grep AnimationConstraint in shipped sources")

    if eval_name == "terrain-grounding-and-lean":
        t, ev = transform_timing(src)
        add("Joint Transforms are written from PreSimulation/Stepped, never from RenderStepped/PreRender", t, ev)
        ok, ev = physics_writes(src)
        add("Never writes physics (root CFrame/velocity, HipHeight, Anchored, WalkSpeed)", ok, ev)
        rays = len(re.findall(r"Raycast\(", code))
        add("Casts rays for the ground (per foot or per body)", rays >= 1, f"Raycast calls={rays}")
        add("Lean is computed from the body's velocity (works for NPCs without input)",
            "AssemblyLinearVelocity" in code or re.search(r"\bVelocity\b", code) is not None, "grep velocity")
        add("Report gives a Studio verification procedure with numeric pass criteria",
            "Studio" in report and re.search(r"-?0\.\d+\s*(stud|studs)?", report) is not None, "grep Studio + numbers")
    elif eval_name == "sword-combo-hitstop":
        spec = read(outputs / "SPEC.md")
        phases = sum(len(re.findall(p, spec)) for p in ["予備動作", "振り", "フォロースルー", "anticipation", "follow"])
        add("SPEC covers anticipation / strike / follow-through for the strikes", phases >= 6, f"phase mentions={phases}")
        add("SPEC states the joint sign conventions", re.search(r"[+＋\-−]\s?X", spec) is not None and "Shoulder" in spec, "grep +X/-X and Shoulder")
        t, ev = transform_timing(src)
        uses_track = re.search(r"AnimationPriority\.Action", code) is not None
        add("Coexists with Animate: Action+ priority track or Transform written after the Animator (PreSimulation)",
            uses_track or t is True, f"actionPriority={uses_track}; {ev}")
        add("Transform writes (if any) are not in RenderStepped/PreRender", t is not False, ev)
        add("Hit-stop implemented", re.search(r"hit.?stop|HitStop|hitStop|ヒットストップ", code) is not None, "grep hitstop")
        ok, ev = physics_writes(src)
        add("Hit-stop / combo never writes physics (root CFrame/velocity, Anchored, WalkSpeed)", ok, ev)
        reg = re.search(r"RegisterKeyframeSequence|RegisterAnimationClip", code) is not None
        add("If KeyframeSequences are registered at runtime, the report says it is Studio-only",
            (not reg) or re.search(r"Studio", report) is not None and re.search(r"本番|production|公開|publish|live", report) is not None,
            f"registers={reg}")
    elif eval_name == "canonical-merge-idle-landing":
        repo = outputs / "mini-game"
        cfg = read(repo / "src/shared/AnimConfig.luau")
        add("Teammate's uncommitted AnimConfig edit (IDLE_BREATH_SECONDS = 2.6) is preserved", "2.6" in cfg and "teammate" in cfg, cfg[-200:])
        log = subprocess.run(["git", "-C", str(repo), "log", "--oneline"], capture_output=True, text=True).stdout.strip().splitlines()
        add("Nothing committed in the user's repository", len(log) == 1, f"commits={len(log)}")
        add("Report diagnoses that RenderStepped Transform writes are not rendered",
            re.search(r"RenderStepped", report) is not None and re.search(r"PreSimulation|Stepped", report) is not None, "grep report")
        t, ev = transform_timing(luau_files(repo / "src", exclude_tests=True))
        add("New code writes Transforms from PreSimulation/Stepped", t, ev)
        original = read(ORIGINAL_GAME)
        # the Place that carries the change: the canonical file updated in place, or a candidate built from it
        places = [p for p in (repo / "places").rglob("*.rbxlx") if "backup" not in p.parts]
        carrying = [p for p in places if ("PreSimulation" in read(p) or ".Stepped" in read(p)) and read(p) != original]
        placed = read(carrying[0]) if carrying else read(repo / "places/Game.rbxlx")
        add("A Place carrying the improved scripts exists (canonical updated, or canonical + layer candidate)",
            bool(carrying), f"carrying={[str(p.relative_to(repo)) for p in carrying]}")
        parts_same = all(re.search(re.escape(name), placed) for name in ["Baseplate", "Ledge"]) and len(placed) > 0
        add("That Place still contains the hand-placed map (not rebuilt from src)", parts_same, f"size={len(placed)}")
        def items(text, cls):
            return re.findall(rf'<Item class="{cls}".*?</Item>', text, flags=re.S)
        same_map = bool(carrying) and items(original, "Part") == items(placed, "Part") and items(original, "SpawnLocation") == items(placed, "SpawnLocation")
        add("Map parts in that Place are byte-identical to the original", same_map, "compared Part/SpawnLocation items")
        add("Report proves the Place change (backup + hash/diff/reversal check)",
            re.search(r"sha256|SHA|ハッシュ|diff|差分|バックアップ|backup|逆", report) is not None, "grep report")
        add("Report gives a Studio verification procedure", "Studio" in report and ("Play" in report or "プレイ" in report), "grep report")
    return exp


def main():
    it = HERE / sys.argv[1]
    summary = []
    for eval_dir in sorted(it.glob("eval-*")):
        name = eval_dir.name[len("eval-"):]
        for run in sorted(p for p in eval_dir.iterdir() if p.is_dir()):
            if not (run / "outputs").exists():
                continue
            exp = grade_run(run, name)
            passed = sum(e["passed"] for e in exp)
            grading = {"expectations": exp, "summary": {"passed": passed, "failed": len(exp) - passed, "total": len(exp),
                                                         "pass_rate": round(passed / len(exp), 3) if exp else 0}}
            (run / "grading.json").write_text(json.dumps(grading, ensure_ascii=False, indent=2), encoding="utf-8")
            summary.append(f"{name:32} {run.name:14} {passed}/{len(exp)}")
            for e in exp:
                if not e["passed"]:
                    summary.append(f"    FAIL {e['text']} :: {e['evidence'][:160]}")
    print("\n".join(summary))


if __name__ == "__main__":
    main()
