# 사용 패턴 (Usage Patterns)

이 페이지는 프로덕션 코드에서 Signal이 일반적으로 어떻게 사용되는지에 중점을 둡니다.

## 이벤트 생성

```luau
local Signal = require(Packages.Signal)
local OnDamage = Signal.new()
```

Signal은 객체, 시스템 또는 기능에 의해 소유되는 재사용 가능한 이벤트 소스를 원할 때 가장 유용합니다.

## 리스너 연결

```luau
local conn = OnDamage:Connect(function(amount)
	print("데미지:", amount)
end)
```

일반적인 리스너에는 `Connect`를 사용하고, 리스너의 생명주기가 확실한 경우 반환된 Connection 객체를 보관하세요.

## 일회성 리스너

```luau
OnDamage:Once(function(amount)
	print("첫 번째 데미지만 감지:", amount)
end)
```

리스너가 단 한 번의 결과만 필요로 할 때 `Once`를 사용합니다.

## 코루틴 내부에서의 대기

```luau
local amount = OnDamage:Wait()
print(amount)
```

`Wait`는 간단한 코루틴 흐름에 유용하지만, 수명이 긴 시스템의 경우 명시적인 리스너가 일반적으로 관리하기 더 쉽습니다.

## 리소스 정리

```luau
conn:Disconnect()
OnDamage:DisconnectAll()
OnDamage:Destroy()
```

소유자가 더 이상 유효하지 않게 되면 Signal을 파괴하세요.

## 실용적인 조언

- Signal의 소유권을 명확히 유지하세요.
- 관찰 대상 객체보다 오래 지속되는 리스너는 연결을 해제하세요.
- 응답 스타일의 흐름에는 `Once`를 사용하세요.
- 오래된 Signal을 방치하지 말고 `Destroy`를 사용하세요.

## 다음 단계

- [설치 방법 (Installation)](./installation.md)
- [Signal API](./signal.md)

## 라이선스

MIT. `LICENSE` 파일을 참조하세요.
