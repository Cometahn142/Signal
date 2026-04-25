# Signal

This page summarizes the public API exposed by the Signal module.

## Constructor

- `Signal.new<T...>() -> Signal<T...>`

## Signal Methods

- `Connect(fn) -> Connection`
- `Once(fn) -> Connection`
- `Wait() -> ...`
- `Fire(...)`
- `DisconnectAll()`
- `Destroy()`

These cover the full listener lifecycle from subscription to cleanup.

## Connection

- `Connection.Connected: boolean`
- `Connection:Disconnect()`

Connections represent a single listener binding.

## Related Docs

- [Installation](./installation.md)
- [Usage Patterns](./usage-patterns.md)

## License

MIT. See `LICENSE`.
