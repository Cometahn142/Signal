# Installation

This page covers the common ways to add Signal to a Roblox project.

## Method 1: Wally

If your project already uses Wally:

```toml
[dependencies]
Signal = "cometahn142/signal@^0.1"
```

Install dependencies through your regular Wally flow, then expose the package
through Rojo or your project loader.

## Method 2: Manual

If you vendor dependencies directly:

1. Copy the module into your project.
2. Name or expose it as `Signal`.
3. Require it from the place where you keep shared utilities.

This approach works fine for smaller projects and prototypes.

## Verification

```luau
local Signal = require(Packages.Signal)
local Event = Signal.new()
Event:Destroy()
```

If the module requires and the signal constructs successfully, the setup is
working.

## Next

- [Usage Patterns](./usage-patterns.md)
- [Signal API](./signal.md)

## License

MIT. See `LICENSE`.
