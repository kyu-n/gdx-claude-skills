# Universal Tween Engine — API Reference

Full method signatures for `aurelienribon.tweenengine` version 6.3.3. Java 8 source level.

## Tween (extends BaseTween\<Tween\>)

### Static Configuration

```java
static void setCombinedAttributesLimit(int limit)   // default 3
static void setWaypointsLimit(int limit)             // default 0
static String getVersion()                           // "6.3.3"
```

### Static Pool

```java
static int getPoolSize()
static void ensurePoolCapacity(int minCapacity)      // default 20
```

### Static Accessor Registration

```java
static void registerAccessor(Class<?> someClass, TweenAccessor<?> defaultAccessor)
static TweenAccessor<?> getRegisteredAccessor(Class<?> someClass)
```

### Static Factories

```java
static Tween to(Object target, int tweenType, float duration)
static Tween from(Object target, int tweenType, float duration)
static Tween set(Object target, int tweenType)              // duration=0
static Tween call(TweenCallback callback)                    // triggers=START, no target
static Tween mark()                                          // empty beacon, no target
```

### Instance — Chaining Methods

```java
Tween ease(TweenEquation easeEquation)
Tween cast(Class<?> targetClass)                // force specific accessor class

Tween target(float targetValue)
Tween target(float v1, float v2)
Tween target(float v1, float v2, float v3)
Tween target(float... targetValues)             // throws if > combinedAttrsLimit

Tween targetRelative(float targetValue)          // offset from value at initialization time
Tween targetRelative(float v1, float v2)          // (after delay), NOT from factory-call time
Tween targetRelative(float v1, float v2, float v3)
Tween targetRelative(float... targetValues)        // finalTarget = startValue + relativeOffset

Tween waypoint(float targetValue)
Tween waypoint(float v1, float v2)
Tween waypoint(float v1, float v2, float v3)
Tween waypoint(float... targetValues)           // throws if waypointsCnt == waypointsLimit

Tween path(TweenPath path)
```

### Instance — Getters

```java
Object getTarget()
int getType()
TweenEquation getEasing()
float[] getTargetValues()
int getCombinedAttributesCount()
TweenAccessor<?> getAccessor()
Class<?> getTargetClass()
```

### Overrides

```java
Tween build()     // validates accessor, computes combinedAttrsCnt
void free()       // returns to pool
```

### Constant

```java
static final int INFINITY = -1    // for repeat()/repeatYoyo() count
```

## Timeline (extends BaseTween\<Timeline\>)

### Static Pool

```java
static int getPoolSize()
static void ensurePoolCapacity(int minCapacity)    // default 10
```

### Static Factories

```java
static Timeline createSequence()
static Timeline createParallel()
```

### Instance — Composition

```java
Timeline push(Tween tween)
Timeline push(Timeline timeline)        // nested timeline must have balanced end() calls
Timeline pushPause(float time)          // negative time = overlap with preceding child

Timeline beginSequence()                // open nested sequence — must close with end()
Timeline beginParallel()                // open nested parallel — must close with end()
Timeline end()                          // close last nested block
```

### Instance — Getters

```java
List<BaseTween<?>> getChildren()        // immutable if built/started
```

### Overrides

```java
Timeline build()     // computes duration from children; throws on infinite-repeat children
Timeline start()     // builds + starts all children
void free()          // frees all children recursively, returns to pool
```

## BaseTween\<T\> (abstract)

### Public API — Chaining

```java
T build()
T start()                              // unmanaged start
T start(TweenManager manager)          // managed start (fire-and-forget)

T delay(float delay)                   // ADDITIVE — stacks with previous calls

T repeat(int count, float delay)       // count=INFINITY for infinite
T repeatYoyo(int count, float delay)   // alternates direction each iteration

T setCallback(TweenCallback callback)
T setCallbackTriggers(int flags)       // bitmask of TweenCallback constants
T setUserData(Object data)
```

### Public API — Control

```java
void kill()
void free()         // abstract — returns to pool
void pause()
void resume()
void update(float delta)               // manual update — always pass delta >= 0
                                       // negative delta backward play is unreliable
```

### Public API — Getters

```java
float getDelay()
float getDuration()                    // single iteration
int getRepeatCount()
float getRepeatDelay()
float getFullDuration()                // delay + duration + (repeatDelay + duration) * repeatCnt
                                       // returns -1 if infinite repeat

Object getUserData()
int getStep()                          // see step encoding below
float getCurrentTime()

boolean isStarted()
boolean isInitialized()                // true after initial delay completes
boolean isFinished()                   // true when done or killed
boolean isYoyo()
boolean isPaused()
```

**Step encoding:**
- -2: initial delay not ended
- -1: before first iteration
- even: iteration playing
- odd: between iterations
- repeatCount*2+1: after last iteration

## TweenManager

### Static Methods

```java
static void setAutoRemove(BaseTween<?> object, boolean value)   // default true
static void setAutoStart(BaseTween<?> object, boolean value)    // default true
```

### Instance Methods

```java
TweenManager add(BaseTween<?> object)
void update(float delta)               // always pass delta >= 0 — negative delta backward
                                       // play is unreliable. Sweeps finished tweens first,
                                       // then updates remaining.

boolean containsTarget(Object target)
boolean containsTarget(Object target, int tweenType)

void killAll()
void killTarget(Object target)
void killTarget(Object target, int tweenType)

void ensureCapacity(int minCapacity)   // default 20
void pause()
void resume()

int size()                             // top-level managed objects count
int getRunningTweensCount()            // recursive tween count (debug)
int getRunningTimelinesCount()         // recursive timeline count (debug)
List<BaseTween<?>> getObjects()        // immutable list (debug)
```

## TweenAccessor\<T\> (interface)

```java
int getValues(T target, int tweenType, float[] returnValues)
    // Write values into returnValues[]. Return count of values written.
    // Count MUST be <= combinedAttrsLimit.

void setValues(T target, int tweenType, float[] newValues)
    // Apply interpolated values to target.
```

## TweenCallback (interface)

```java
void onEvent(int type, BaseTween<?> source)
    // 'type' is a SINGLE flag, not a combined mask
```

### Constants (bitmask flags)

| Constant | Value |
|---|---|
| `BEGIN` | 0x01 |
| `START` | 0x02 |
| `END` | 0x04 |
| `COMPLETE` | 0x08 |
| `BACK_BEGIN` | 0x10 |
| `BACK_START` | 0x20 |
| `BACK_END` | 0x40 |
| `BACK_COMPLETE` | 0x80 |
| `ANY_FORWARD` | 0x0F |
| `ANY_BACKWARD` | 0xF0 |
| `ANY` | 0xFF |

## TweenEquation (abstract class)

```java
abstract float compute(float t)        // t in [0, 1], returns interpolated value
boolean isValueOf(String str)          // matches toString()
```

## Easing Equations

All in `aurelienribon.tweenengine.equations`:

| Class | Variants | Parameterizable |
|---|---|---|
| `Linear` | `INOUT` only | No |
| `Quad` | `IN`, `OUT`, `INOUT` | No |
| `Cubic` | `IN`, `OUT`, `INOUT` | No |
| `Quart` | `IN`, `OUT`, `INOUT` | No |
| `Quint` | `IN`, `OUT`, `INOUT` | No |
| `Circ` | `IN`, `OUT`, `INOUT` | No |
| `Sine` | `IN`, `OUT`, `INOUT` | No |
| `Expo` | `IN`, `OUT`, `INOUT` | No |
| `Back` | `IN`, `OUT`, `INOUT` | `s(float)` — overshoot, default 1.70158 |
| `Bounce` | `IN`, `OUT`, `INOUT` | No |
| `Elastic` | `IN`, `OUT`, `INOUT` | `a(float)` — amplitude; `p(float)` — period |

**`Back.s()` and `Elastic.a()`/`p()` mutate the static instance fields.** Not thread-safe. Persists for application lifetime.

### TweenEquations Interface

Alternative named references (implement this interface for convenient access):

```java
easeNone = Linear.INOUT
easeInQuad = Quad.IN        easeOutQuad = Quad.OUT        easeInOutQuad = Quad.INOUT
easeInCubic = Cubic.IN      easeOutCubic = Cubic.OUT      easeInOutCubic = Cubic.INOUT
// ... same pattern for Quart, Quint, Circ, Sine, Expo, Back, Bounce, Elastic
```

### TweenUtils

```java
static TweenEquation parseEasing(String easingName)  // e.g., "Quad.INOUT" -> Quad.INOUT
                                                      // returns null if no match
```

## TweenPath (interface)

```java
float compute(float t, float[] points, int pointsCnt)
```

## TweenPaths (built-in path instances)

```java
static final Linear linear           // piecewise linear between waypoints
static final CatmullRom catmullRom   // smooth Catmull-Rom spline (DEFAULT)
```

## Primitives (self-implementing TweenAccessor)

### MutableFloat

```java
// extends Number, implements TweenAccessor<MutableFloat>
MutableFloat(float value)
void setValue(float value)
// Number methods: intValue(), longValue(), floatValue(), doubleValue()
// TweenAccessor: getValues/setValues — tweenType is ignored, always 1 combined attr
```

### MutableInteger

```java
// extends Number, implements TweenAccessor<MutableInteger>
MutableInteger(int value)
void setValue(int value)
// Number methods: intValue(), longValue(), floatValue(), doubleValue()
// TweenAccessor: getValues/setValues — tweenType is ignored, always 1 combined attr
// Note: setValues truncates float to int
```
