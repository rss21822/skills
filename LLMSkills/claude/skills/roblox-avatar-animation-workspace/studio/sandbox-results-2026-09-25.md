# AnimSandbox measurements (2026-09-25)

Place: `studio/AnimSandbox.rbxlx` from `scripts/make_test_place.py` (Baseplate, 22-degree slope, 1-stud stairs).
Avatar: the Studio user's R15 avatar (AnimationConstraint rig), stock Roblox Animate script, WalkSpeed 16.
Driver: client Humanoid:MoveTo route (flat, stairs up/down x2, slope up/down, 16-point circle r=10), same route with the
layer OFF (`PoseLayerOff` = true) and ON. Probe: `scripts/studio/contact_probe.luau` (toe/heel rays from root height).

Grounded frames. minGap = lowest foot minus its floor; lower = the planted foot's gap; sink = any foot < -0.05; float = lower > 0.1.

| floor, motion | OFF sink / float / lowerMean | ON sink / float / lowerMean |
|---|---|---|
| Baseplate, moving (n~1060) | 268 / 421 / +0.086 | 8 / 0 / -0.001 |
| Slope, moving (n~395) | 297 / 53 / -0.242 | 3 / 0 / -0.002 |
| Stairs, moving (n~380) | 198 / 90 / -0.137 | 54 / 59 / +0.001 |
| Standing (spawn, flat, slope top, stairs) | up to 19 sink | 0 / 0 / 0.000 (max 0.007) |

Console: 0 errors. Stairs while moving keep a residual: the Humanoid pops the root up/down a step during the physics
step that follows the PreSimulation write, so the drawn body is one step behind for a frame or two.

Earlier runs: centre-of-foot rays starting 1.5 above the foot reported feet 2.8-3.0 "floating" on stairs and slopes
(the ray started inside the step and hit the ground below) -> rays now start at root height; one ray per foot left
feet across a step edge sinking -> toe + heel rays, higher hit wins. Keeping authored lift above flat ground kept the
stock run's flight phase (lower foot up to 0.45 above the floor on flat ground) -> default now plants the lower foot,
`keepFlight` opt-in.
