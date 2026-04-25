# Usage Patterns

This page focuses on how Signal is usually used in production code.

## Creating an event

```luau
local Signal = require(Packages.Signal)
local OnDamage = Signal.new()
```

Signals are best used when you want a reusable event source owned by an object,
system, or feature.

## Connecting listeners

```luau
local conn = OnDamage:Connect(function(amount)
	print("Damage:", amount)
end)
```

Use `Connect` for standard listeners and keep the returned connection when the
listener has a real lifecycle.

## One-shot listeners

```luau
OnDamage:Once(function(amount)
	print("First damage only:", amount)
end)
```

Use `Once` when the listener only needs a single result.

## Waiting inside coroutines

```luau
local amount = OnDamage:Wait()
print(amount)
```

`Wait` is handy for simple coroutine flows, but for longer-lived systems,
explicit listeners are usually easier to manage.

## Cleanup

```luau
conn:Disconnect()
OnDamage:DisconnectAll()
OnDamage:Destroy()
```

Destroy the signal when its owner is no longer valid.

## Practical Advice

- Keep signal ownership clear.
- Disconnect listeners that outlive the object they observe.
- Use `Once` for response-style flows.
- Use `Destroy` instead of leaving old signals around.

## Next

- [Installation](./installation.md)
- [Signal API](./signal.md)

## License

MIT. See `LICENSE`.
