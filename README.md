# Signal

Signal is a lightweight event library for Luau focused on fast dispatch,
predictable listener behavior, and straightforward cleanup.

It is meant to replace ad-hoc callback lists with a small, reusable event
primitive that feels natural in gameplay code.

## Features

- Fast `Connect` and `Fire`
- One-shot listeners with `Once`
- Coroutine-friendly `Wait`
- Cleanup via `DisconnectAll` and `Destroy`
- Connection objects that expose `Connected`

## Installation

```toml
[dependencies]
Signal = "cometahn142/signal@^0.1"
```

## Quick Example

```luau
local Signal = require(Packages.Signal)

local OnDamage = Signal.new()
local conn = OnDamage:Connect(function(amount)
	print("Damage:", amount)
end)

OnDamage:Fire(25)
conn:Disconnect()
OnDamage:Destroy()
```

## Documentation

- [Installation](./docs/installation.md)
- [Usage Patterns](./docs/usage-patterns.md)
- [Signal API](./docs/signal.md)

## License

MIT. See `LICENSE`.
