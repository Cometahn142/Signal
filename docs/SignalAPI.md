## Signal API

This document describes the public API exported by `src/init.luau`.

## Creating a signal

```lua
local Signal = require(path.to.Signal)

local sig = Signal.new()
```

### `Signal.new()`

- **Returns**
  - `Signal<T...>`
- **Notes**
  - Handlers are dispatched using `task.spawn` via a cached runner coroutine, so yielding handlers are supported.

## Connecting

### `sig:Connect(fn) -> Connection`

- Connects a handler.
- **Ordering**
  - New connections run before older ones (`LIFO`), since handlers are inserted at the head of an internal list.

### `sig:Once(fn) -> Connection`

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

- Dispatches handlers using `task.spawn`.

## Waiting

### `sig:Wait() -> ...`

- Yields the current coroutine until the next `Fire`.

## Bulk operations / lifecycle

### `sig:DisconnectAll()`

- Disconnects every current handler.
- Safe during `Fire` (recycling is deferred until firing completes).

### `sig:Destroy()`

- Disconnects all handlers and marks the signal as destroyed.
- Any later method call errors.
