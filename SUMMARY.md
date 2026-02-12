# Skills Test Harness: What It Does and Why It Matters

## What This Repository Contains

**28 Claude Code skills** and a **59-prompt automated test harness** that measure whether skills improve Claude's accuracy on game development questions.

### Components

| Component | Description |
|---|---|
| `skills/` | 28 reference skills (27 libGDX + 1 Universal Tween Engine), each a `SKILL.md` correcting specific model blind spots |
| `test_prompts.json` | 59 test prompts with machine-gradeable criteria, keyword anchors, and anti-pattern traps |
| `run_tests.sh` | Test harness: runs each prompt N times with/without skills, grades with the test model, adjudicates with Opus |
| `README.md` | Harness usage, cost estimates, output format |

### Test Roles

Each test prompt is tagged with a role indicating what it measures:

| Role | Count | Purpose |
|---|---|---|
| **canary** | 44 | Regression guards — both arms should pass; detects skill-induced regressions |
| **discriminating** | 13 | Baseline fails, skill fixes — proves the skill provides new knowledge |
| **anomaly** | 1 | Monitors for unexpected skill-induced regressions |
| **skill-resistant** | 1 | Both arms may fail — tracks hard problems |

## How Skills Improve Performance

### Discriminating Tests (13 tests across 9 skills)

Tested on 13 discriminating tests (where baseline is known to fail). 1 run per arm, Opus adjudicator.

**Haiku:**

| Arm | Pass | Fail | Rate |
|---|---|---|---|
| Baseline (no skills) | 6 | 7 | 46% |
| With skills | 13 | 0 | 100% |
| **Delta** | | | **+54pp** |

**Sonnet:**

| Arm | Pass | Fail | Rate |
|---|---|---|---|
| Baseline (no skills) | 9 | 4 | 69% |
| With skills | 12 | 1 | 92% |
| **Delta** | | | **+23pp** |

Zero regressions on both models. Haiku benefits ~2x more from skills than Sonnet, as expected for a smaller model.

### What skills fix

| Test | What the model gets wrong without skills | What the skill corrects |
|---|---|---|
| `ios-01` | Recommends deprecated `gdx-backend-robovm` | MetalANGLE backend for new projects (Apple deprecated OpenGL ES) |
| `lwjgl3-03` | Claims `pause()` fires on Alt+Tab | `Lwjgl3WindowListener.focusLost()` — pause only fires on minimize |
| `net-03` | Claims `downloadComplete()` runs on background thread | Already on GL thread (internal postRunnable) |
| `math-04` | Doesn't distinguish int vs float `MathUtils.random()` bounds | `random(int,int)` inclusive, `random(float,float)` exclusive upper |
| `json-02` | Omits `Array.size` is a field, not method | Public field, plus identity parameter and nulls-beyond-size warning |
| `box2d-03` | Passes `getDeltaTime()` directly to `world.step()` | Fixed timestep accumulator pattern |
| `tween-01` | Omits `setCombinedAttributesLimit(4)` for RGBA | Default limit is 3; tweening 4+ values throws without raising it |
| `tween-02` | Omits `setWaypointsLimit(n)` for waypoints | Default limit is 0; any `.waypoint()` call throws without raising it |
| `tween-04` | Says duration is in "seconds" | Duration is unitless — matches whatever you pass to `manager.update(delta)` |

## How the Test Harness Works

```
Per test, per arm (baseline + skills):

  N× independent runs (test model)
       ↓
  N× independent grades (test model)
       ↓
  1× adjudication (Opus)
       ↓
  Final verdict + confidence + classification
```

The multi-run + adjudication design filters out sampling noise. A single run might fluke pass or fail; multiple runs with Opus adjudication reliably identifies whether the underlying *model behavior* passes or fails.

### Grading Criteria

Each test has three layers of criteria:

1. **`must_contain`** — keywords that must be semantically present (e.g., `"setCombinedAttributesLimit"`)
2. **`must_not_contain`** — anti-patterns that fail the test unless the response explicitly warns against them (e.g., `"new Tween("`, `"repeatYoyo(true)"`)
3. **`criteria`** — holistic natural-language grading rubric applied by the grader model

### Adjudicator Classifications

| Classification | Meaning | Actionable? |
|---|---|---|
| `clear_pass` | All/nearly all runs pass | No |
| `clear_fail` | All/nearly all runs fail for the same reason | **Fix the skill** |
| `noise` | Runs disagree due to sampling variation | No |
| `edge_case` | Criteria boundary is genuinely unclear | Maybe — tighten test |
| `grader_error` | Individual grader misapplied criteria; adjudicator corrects | Maybe — fix test wording |

## Skill Design Philosophy

Each skill is a concise reference document that corrects specific, documented gaps in the base model's knowledge. Skills are written by:

1. **Running a baseline** without the skill to identify what the model gets wrong
2. **Reading the library source code** to determine the correct behavior
3. **Writing the skill** to cover exactly those gaps — no more, no less
4. **Testing with the harness** to confirm the skill closes all gaps without regressions

Skills target *semantic traps* — places where the correct API behavior is surprising, poorly documented, or contradicts common patterns. They don't repeat information the model already knows.
