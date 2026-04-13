# Signal

High-performance Luau `Signal` with:
- Fast `Fire` hot path (runner coroutine cache for yield-safe handlers)
- O(1) `Disconnect`
- Node pooling + safe re-entrancy during `Fire`

```lua
local Signal = require(path.to.Signal)

local sig = Signal.new() -- default: "spawn"
sig:Connect(function(x)
	print("got", x)
end)
sig:Fire(123)
```

## Docs

- [`docs/WhyUseSignal.md`](docs/WhyUseSignal.md)
- [`docs/SignalAPI.md`](docs/SignalAPI.md)
