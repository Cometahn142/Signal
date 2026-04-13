## Signal API

This document describes the public API exported by `src/init.luau`.

## Creating a signal

```lua
local Signal = require(path.to.Signal)

local sig = Signal.new() -- same as Signal.new("spawn")
local syncSig = Signal.new("sync")
local deferSig = Signal.new("defer")
local spawnSig = Signal.new("spawn")
```

### `Signal.new(mode?)`

- **Parameters**
  - `mode`: `"sync" | "defer" | "spawn"` (optional)
- **Returns**
  - `Signal<T...>`
- **Notes**
  - `"sync"` is fastest but **not yield-safe**.
  - `"spawn"` is the default.

## Connecting

### `sig:Connect(fn, priority?) -> Connection`

- Connects a handler.
- `priority` defaults to `0`.
- **Ordering**
  - Higher priority runs earlier.
  - When no non-zero priorities exist, `priority = 0` uses the fast O(1) head-insert path.

### `sig:ConnectWithPriority(priority, fn) -> Connection`

- Same as `Connect`, but requires an explicit priority.
- May be **O(n)** due to sorted insertion.

### `sig:Once(fn, priority?) -> Connection`

- Connects a handler that disconnects itself after the first run.

## Connection handle

### `connection.Connected: boolean`

- True while the connection is active.

### `connection:Disconnect()`

- Disconnects the handler.
- Safe to call multiple times.
- **Complexity**: O(1)

## Firing

### `sig:Fire(...)`

- Dispatches using the mode chosen in `Signal.new`.

### `sig:FireSync(...)`

- Forces synchronous dispatch (inline on the caller thread).

### `sig:FireDeferred(...)`

- Forces deferred dispatch via `task.defer`.

### `sig:FireSpawn(...)`

- Forces spawned dispatch via `task.spawn`.

## Waiting

### `sig:Wait() -> ...`

- Yields the current coroutine until the next `Fire`.

### `sig:WaitTimeout(timeout) -> (boolean, ...)`

- Yields until the next `Fire` or until `timeout` seconds elapse.
- Returns `(true, ...)` when fired.
- Returns `(false)` on timeout.

## Bulk operations / lifecycle

### `sig:DisconnectAll()`

- Disconnects every current handler.
- Safe during `Fire` (recycling is deferred until firing completes).

### `sig:GetConnectionCount() -> number`

- O(1) number of active handlers.

### `sig:HasConnections() -> boolean`

- O(1) convenience check (`count > 0`).

### `sig:Destroy()`

- Disconnects all handlers and marks the signal as destroyed.
- Any later method call errors.
