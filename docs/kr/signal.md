# Signal

이 페이지는 Signal 모듈이 제공하는 공개 API를 요약합니다.

## 생성자

- `Signal.new<T...>() -> Signal<T...>`

## Signal 메서드

- `Connect(fn) -> Connection`
- `Once(fn) -> Connection`
- `Wait() -> ...`
- `Fire(...)`
- `DisconnectAll()`
- `Destroy()`

이 메서드들은 구독부터 정리까지의 전체 리스너 생명주기를 처리합니다.

## 연결 (Connection)

- `Connection.Connected: boolean`
- `Connection:Disconnect()`

연결 객체는 단일 리스너 바인딩을 나타냅니다.

## 관련 문서

- [설치 방법 (Installation)](./installation.md)
- [사용 패턴 (Usage Patterns)](./usage-patterns.md)

## 라이선스

MIT. `LICENSE` 파일을 참조하세요.
