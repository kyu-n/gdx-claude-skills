# libGDX Claude Code Skills

28 [Claude Code skills](https://docs.anthropic.com/en/docs/claude-code/skills) that correct documented blind spots in Claude's knowledge of libGDX and related game development libraries. Each skill is a concise reference document targeting specific API traps, surprising behaviors, and poorly documented features that the base model gets wrong.

Designed for **libGDX 1.14.1** (HEAD). Validated against **Claude Sonnet 4.5** with a 59-test automated harness — 100% pass rate with skills, zero regressions.

> **Version notice:** These skills are verified against libGDX 1.14.1 (current HEAD) and Claude model versions Opus 4.6, Sonnet 4.5, and Haiku 4.5. Future libGDX releases may change APIs, defaults, or behavior that these skills document. Future model versions may fix (or introduce) blind spots that shift which skills provide value. If you're using a different libGDX version or a newer Claude model, verify claims against source before relying on them.

## Installation

Copy the skills you need into your project's `.claude/skills/` directory or your user-level `~/.claude/skills/` directory:

```bash
# All skills
cp -r skills/* ~/.claude/skills/

# Or specific skills
cp -r skills/libgdx-box2d ~/.claude/skills/
cp -r skills/libgdx-2d-rendering ~/.claude/skills/
```

Claude Code automatically loads matching skills based on their `description` field when relevant to the conversation.

## What Problems Do These Solve?

Claude's training data covers libGDX, but the model consistently gets specific details wrong — deprecated methods presented as current, constructor signatures with wrong argument order, invented APIs that don't exist, and subtle behavioral details (like `coneDegrees` being a half-angle, not full arc). These aren't gaps in general understanding; they're precise factual errors that produce code that compiles but behaves incorrectly.

Each skill was written by:

1. Running a baseline without the skill to identify specific, reproducible errors
2. Reading library source code to determine correct behavior
3. Writing a correction targeting exactly those gaps
4. Validating with the test harness to confirm fixes with zero regressions

## What These Skills Fix

Below are some examples of when Claude gets specific libGDX details wrong. For some categories, code compiles but behaves incorrectly or crashes at runtime.

| Category | What Claude says | What's actually true |
|---|---|---|
| Deprecated API | `config.renderInterval = 1/20f` | `renderInterval` removed in 1.9.14; use `config.updatesPerSecond = 20` (int) |
| Deprecated backend | Recommends `gdx-backend-robovm` for iOS | Apple deprecated OpenGL ES; use `gdx-backend-robovm-metalangle` |
| Wrong threading | `downloadComplete()` runs on background thread | Already on GL thread (internal `postRunnable`) |
| Wrong lifecycle | `pause()` fires on Alt+Tab (LWJGL3) | Only fires on minimize; use `Lwjgl3WindowListener.focusLost()` |
| Wrong defaults | `preferredFramesPerSecond` defaults to 60 (iOS) | Defaults to 0 (= max supported by screen) |
| Invented API | `Color.CORNFLOWER_BLUE` | No such constant in libGDX; use `Color.SKY` or raw floats |
| Invented API | `window.getContentTable()` | `getContentTable()` is on `Dialog`, not `Window` — Window extends Table directly |
| Missing method | InputProcessor has 8 methods | Has 9 — `touchCancelled` is consistently omitted |
| Subtle bounds | `MathUtils.random()` treats int and float the same | `random(int,int)` inclusive upper; `random(float,float)` exclusive upper |
| Wrong class | `MessageDispatcher.getInstance()` (gdx-ai) | `MessageManager.getInstance()` — MessageDispatcher has no `getInstance()` |

Validated with an automated test harness (59 tests, 3 runs per arm, Opus adjudicator). See `SUMMARY.md` for methodology and full results.

## Skills

### Core

| Skill | Covers |
|---|---|
| `libgdx-application-lifecycle` | ApplicationListener/Adapter, create vs constructor, render = update + draw, delta time, pause/resume platform differences, Disposable types |
| `libgdx-audio-lifecycle` | Sound vs Music, pan (mono only), Android 1MB limit, OGG unsupported on iOS, OnCompletionListener + looping incompatibility, Music auto-pause |
| `libgdx-input-handling` | Polling vs event-driven, InputProcessor/InputAdapter, InputMultiplexer, coordinate unprojection, GestureDetector, scrolled() direction, Android back/menu keys |
| `libgdx-file-io-preferences` | FileHandle/FileType, platform-specific paths, local vs internal vs external, Preferences API |

### Rendering

| Skill | Covers |
|---|---|
| `libgdx-2d-rendering` | SpriteBatch, ShapeRenderer, Texture/TextureRegion/TextureAtlas, TextureFilter, Camera/Viewport, draw ordering, ScreenUtils.clear() |
| `libgdx-camera-viewport` | OrthographicCamera, PerspectiveCamera, Viewport types (Fit/Fill/Stretch/Extend/Screen), resize handling, coordinate unprojection |
| `libgdx-graphics-3d` | ModelBatch, ModelInstance, G3DJ/G3DB/OBJ loading, ModelBuilder, Environment/lighting, Materials/Attributes, AnimationController |
| `libgdx-shaders` | ShaderProgram, GLSL, custom SpriteBatch shaders, Mesh rendering, uniform/attribute setup |
| `libgdx-framebuffer-pixmap` | FrameBuffer (FBO), render-to-texture, post-processing, Pixmap, runtime texture generation, screen capture |
| `libgdx-particles` | 2D/3D ParticleEffect, ParticleEffectPool, blend functions, AssetManager integration |

### Text and UI

| Skill | Covers |
|---|---|
| `libgdx-bitmap-font-text` | BitmapFont, GlyphLayout, BitmapFontCache, NinePatch, DistanceFieldFont, color markup |
| `libgdx-freetype` | FreeTypeFontGenerator, density scaling, characters param, incremental CJK rendering, AssetManager integration, iOS forceLinkClasses |
| `libgdx-scene2d-ui` | Stage, Table layout, Skin, widgets, ChangeListener/ClickListener, Actions system, InputMultiplexer, Viewport integration |

### Physics and Lighting

| Skill | Covers |
|---|---|
| `libgdx-box2d` | World/Body/Fixture, collision filtering, ContactListener, joints, Box2DDebugRenderer, pixels-to-meters, fixed timestep |
| `libgdx-box2dlights` | RayHandler/RayHandlerOptions, PointLight/ConeLight/DirectionalLight/ChainLight, shadow filtering, setStaticLight/setXray optimizations |
| `libgdx-bullet-physics` | btRigidBody, btDiscreteDynamicsWorld, collision shapes, ContactListener, raycasting, MotionState, native memory lifecycle |

### Data and Assets

| Skill | Covers |
|---|---|
| `libgdx-assetmanager` | Async loading, reference counting, screen transitions, custom loaders, FreeType font loading, Android context loss recovery |
| `libgdx-collections-json` | Array/ObjectMap/ObjectSet/Queue, Pool, Json serialization, I18NBundle, Timer, identity parameter gotchas |
| `libgdx-math` | Vector2/Vector3/Matrix4, MathUtils, Interpolation, Intersector, mutation bugs, int vs float random() bounds |
| `libgdx-networking` | Gdx.net HTTP requests, TCP sockets, response threading (GL thread vs background) |
| `libgdx-tiled` | TmxMapLoader, TiledMap, TiledMapTileLayer, OrthogonalTiledMapRenderer, object layers, unitScale |

### Platform Backends

| Skill | Covers |
|---|---|
| `libgdx-android-backend` | AndroidApplication, AndroidManifest.xml configChanges, GL context loss on ALL versions, file access paths, safe insets, immersive mode |
| `libgdx-lwjgl3-desktop` | Lwjgl3Application, setForegroundFPS vs useVsync (independent), pause only on minimize (not focus loss), multi-window, Lwjgl3WindowListener |
| `libgdx-ios-robovm` | IOSApplication, MetalANGLE backend, robovm.xml forceLinkClasses, GL context preserved (unlike Android), useHaptics, safe area insets |
| `libgdx-headless-backend` | HeadlessApplication, updatesPerSecond (not the old renderInterval), Gdx.gl is null, what works vs what crashes |

### Extensions

| Skill | Covers |
|---|---|
| `libgdx-controllers` | gdx-controllers 2.x API (not 1.x), ControllerMapping, ControllerListener (5 methods), dead zones, Gradle dependencies |
| `libgdx-gdx-ai` | Steering behaviors, A* pathfinding, behavior trees (.tree format), FSM/MessageManager (Telegraph refs not int IDs) |

### Other Libraries

| Skill | Covers |
|---|---|
| `universal-tween-engine` | Tween.to/from/set, Timeline, TweenAccessor, setCombinedAttributesLimit, setWaypointsLimit, duration is unitless, repeatYoyo signature |