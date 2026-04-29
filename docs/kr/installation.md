# 설치 방법

이 페이지에서는 Roblox 프로젝트에 Signal을 추가하는 일반적인 방법을 설명합니다.

## 방법 1: Wally

프로젝트에서 이미 Wally를 사용하는 경우:

```toml
[dependencies]
Signal = "cometahn142/signal@^0.1"
```

일반적인 Wally 워크플로우를 통해 종속성을 설치한 다음, Rojo 또는 프로젝트 로더를 통해 패키지를 노출합니다.

## 방법 2: 수동 설치

종속성을 직접 포함하는 경우:

1. 모듈을 프로젝트에 복사합니다.
2. 이름을 `Signal`로 지정하거나 노출합니다.
3. 공통 유틸리티를 보관하는 위치에서 불러옵니다(Require).

이 방법은 소규모 프로젝트 및 프로토타입에 적합합니다.

## 검증

```luau
local Signal = require(Packages.Signal)
local Event = Signal.new()
Event:Destroy()
```

모듈을 성공적으로 불러오고 Signal이 생성되면 설정이 올바르게 작동하는 것입니다.

## 다음 단계

- [사용 패턴 (Usage Patterns)](./usage-patterns.md)
- [Signal API](./signal.md)

## 라이선스

MIT. `LICENSE` 파일을 참조하세요.
