<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-client-dark.svg">
    <img src="cutaway-client-light.svg" alt="Cutaway — iOS 인터페이스를 레이어 단위로 들여다봅니다." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue)](#requirements)
[![License](https://img.shields.io/badge/License-GPL--3.0-lightgrey)](../../LICENSE)
[![check](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml/badge.svg)](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | **한국어** | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*이 문서는 번역본입니다. 내용이 다를 경우 [영어 README](../../README.md)가 우선합니다.*

Cutaway는 실행 중인 iOS 앱의 인터페이스 내부를 들여다보기 위한 macOS 앱입니다. 앱에
[CutawayServer](https://github.com/nothingsh/CutawayServer)를 추가하고 시뮬레이터나 USB로 연결된
기기에서 실행하면 Cutaway의 목록에 나타납니다. 선택하면 Cutaway는 앱의 레이어 트리, 모든 레이어의
스크린샷을 2D로 펼쳐 놓거나 3D로 벌려 놓은 모습, 그리고 선택한 레이어의 속성과 Auto Layout 제약
조건을 보여 줍니다. 속성에 가한 편집은 실행 중인 앱에 적용됩니다.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="overview-dark.png">
    <img src="overview-light.png" alt="Cutaway가 앱을 3D로 검사하는 모습: 레이어 트리, 벌려 놓은 레이어와 측정값, 선택한 레이어의 속성." width="850">
  </picture>
</p>

<a id="features"></a>
## 기능

**인터페이스가 어떻게 구성되어 있는지 보기**

- 모든 윈도우의 레이어 트리. 뷰 컨트롤러의 루트 뷰와, 각 레이어나 뷰를 보유한 멤버 변수가
  표시되므로 레이어를 코드까지 거슬러 올라갈 수 있습니다.
- 모든 레이어의 스크린샷을 2D로 평평하게, 또는 3D로 벌려서. 마우스나 트랙패드로 회전하고
  확대/축소하고 이동하며, 레이어 사이의 간격을 바꾸고, 가려진 레이어를 표시할 수 있습니다.
- 3D 변환을 포함하여, 기기 화면에서와 똑같은 모든 위치, 크기, 회전, 배율.
- 측정: ⌥를 누른 채 다른 레이어를 가리키면 그 레이어와 선택한 레이어 사이의 거리가 2D와 3D로
  표시됩니다.

**세부 정보 다루기**

- 선택한 레이어와 뷰의 속성. 앱이 보고하는 대로 그룹화됩니다. 편집 가능한 속성에는 컨트롤이
  있습니다. 텍스트, 드래그할 수 있는 숫자, 스위치, 색상 선택기, 열거형을 위한 팝업. 변경은
  실행 중인 앱에 즉시 적용되며, ⌘Z로 되돌릴 수 있습니다.
- 선택한 뷰를 참조하는 Auto Layout 제약 조건. 적용되지 않은 것은 표시되고, 각 제약 조건의
  반대편은 미리보기에 표시됩니다. 반대편을 클릭하면 그곳으로 이동합니다.
- 트리 검색, 하위 트리에 초점 맞추기, 지정한 깊이까지 펼치기, 하위 트리만 새로 고침.

**찾은 것 보관하기**

- 검사를 `.cutaway` 아카이브로 저장하고, 나중에 기기 없이 어느 Mac에서든 열 수 있습니다.
  트리, 스크린샷, 속성, 제약 조건이 모두, 보고 있던 보기 그대로 들어 있습니다.
- 레이어의 스크린샷을 단독으로 또는 하위 레이어를 포함하여 PNG로 내보냅니다.

**일상적인 사용을 위한 설계**

- 앱을 스스로 찾습니다. 이 Mac의 시뮬레이터와 USB로 연결된 기기에서.
- 트리를 먼저 보여 주고 스크린샷은 도착하는 대로 보여 줍니다. 큰 트리도 응답성을 유지합니다.
- 앱이 돌아오면 다시 연결합니다. 앱의 상태를 따라갑니다. 앱이 백그라운드로 가면 Cutaway가
  그렇다고 알리고, 돌아오면 계속합니다.
- 영어, 중국어 간체, 중국어 번체, 일본어, 한국어를 지원합니다.
- 이 Mac의 앱과 USB 케이블을 통해서만 통신합니다. 분석 데이터도, 충돌 보고도 없습니다.

<a id="requirements"></a>
## 요구 사항

- macOS 14 이상. Metal을 지원하는 GPU가 있는 Mac (macOS 14를 실행하는 모든 Mac).
- [CutawayServer](https://github.com/nothingsh/CutawayServer)를 포함한 앱이 iOS Simulator에서,
  또는 USB로 Mac에 연결된 iPhone이나 iPad에서 실행 중이어야 합니다.

Cutaway는 샌드박스를 사용하지 않습니다. USB로 기기에 접근하는 데 사용하는 소켓이 샌드박스
바깥에 있기 때문입니다. 같은 이유로 Mac App Store 밖에서 배포됩니다.

<a id="installation"></a>
## 설치

[Releases](https://github.com/nothingsh/Cutaway/releases) 페이지에서 `Cutaway-<버전>.dmg`를 다운로드해 열고, Cutaway를
응용 프로그램 폴더로 드래그하세요. Cutaway는 오픈 소스이며 빌드는 Apple의 공증을 받지 않았습니다.
그래서 처음 열 때 macOS가 개발자를 확인할 수 없다고 알립니다. **시스템 설정 › 개인정보 보호 및
보안**을 열고 **그래도 열기**를 선택하거나, 다음을 실행하세요.

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › 업데이트 확인…**으로 더 새로운 릴리스가 나왔는지 확인할 수 있습니다. 소스에서
Cutaway를 빌드할 수도 있습니다. [개발](#development)을 참조하세요.

## 빠른 시작

1. iOS 앱에 [CutawayServer](https://github.com/nothingsh/CutawayServer)를 추가하고 시작 시 `CutawayServer.start()`를 한 번 호출합니다. 서버의
   [README](https://github.com/nothingsh/CutawayServer#readme)에 UIKit과 SwiftUI용 두 줄이
   있습니다. Debug 빌드에만 컴파일됩니다.
2. 시뮬레이터에서, 또는 케이블로 Mac에 연결된 기기에서 앱을 실행합니다.
3. Cutaway를 엽니다. 몇 초 안에 앱이 목록에 나타납니다. 선택하세요.

## Cutaway 사용하기

### 레이어 목록

사이드바에는 모든 윈도우의 레이어가 트리로 나열됩니다. 각 행에는 레이어의 클래스, 레이어가
뒷받침하는 뷰, 그 뷰를 루트 뷰로 하는 뷰 컨트롤러, 그리고 레이어를 보유한 멤버 변수(예:
`HomeViewController.titleLabel`)가 표시됩니다. 흐리게 표시된 행은 가려져 있거나 완전히 투명한
레이어입니다.

- 맨 위의 필드로 트리를 **필터**합니다. 제목이나 클래스에 입력한 텍스트가 포함된 행이 조상과
  함께 남습니다.
- 레이어에 **초점을 맞추면**(⌥⌘↓) 목록과 미리보기에 그 하위 트리만 표시됩니다. 목록 위의
  경로를 따라 다시 빠져나올 수 있습니다.
- 필터 옆의 메뉴에서 지정한 수준까지, 또는 전부 **펼칩니다**(전부는 ⌥⌘→와 ⌥⌘←). 앱을 처음
  검사할 때는 화면에 있는 뷰 컨트롤러까지 트리가 펼쳐집니다.
- 행을 **두 번 클릭**하면 펼치거나 접습니다. 미리보기에서 레이어를 두 번 클릭해도 같은 동작을
  합니다.

### 미리보기

미리보기는 트리가 도착하는 대로, 그리고 각 스크린샷이 도착하는 대로, 보이는 모든 레이어를
화면의 제자리에 스크린샷과 함께 그립니다.

- 툴바에서 **2D 또는 3D**(⌘1, ⌘2)를 선택합니다. 3D에서는 레이어가 깊이에 따라 벌려지며,
  목록에서 행을 접으면 그 하위 트리가 다시 하나로 포개집니다.
- 3D에서는 드래그하여 **회전**하고, 스크롤하거나 2D에서는 드래그하여 **이동**하고, 핀치하거나
  ⌘와 스크롤 휠로 포인터를 중심으로 **확대/축소**합니다. **보기 재설정**(⌘0)은 처음 상태로
  돌아갑니다.
- 3D의 **레이어 간격**은 미리보기 아래의 슬라이더로 조절하며, 0부터 200포인트까지입니다.
- **가려진 레이어 보기**(⇧⌘H)는 가려져 있거나 투명한 레이어도 고유한 스타일로 그립니다.
  **테두리 보기**(⇧⌘B)는 모든 레이어의 윤곽선을 그립니다. 두 스위치는 미리보기 아래에도
  있습니다.
- **측정**: 레이어를 선택한 상태에서 ⌥를 누른 채 다른 레이어를 가리킵니다. 두 레이어 사이의
  거리가 포인트 단위의 값과 함께 2D와 3D로 그려집니다.
- 레이어를 클릭하면 선택되며, 목록과 속성이 따라갑니다. 포인터 아래의 레이어는 강조
  표시됩니다.

### 속성

오른쪽의 속성 패널에는 선택한 레이어와 그 뷰의 속성이 `layer`, `view`, `label` 같은, 앱이
보고하는 그룹으로 표시됩니다. Cutaway에는 자체 목록이 없습니다. 표시되는 것은 [CutawayServer](https://github.com/nothingsh/CutawayServer)가
보내는 것이므로, 앱에 포함된 서버 버전이 아는 것은 무엇이든 보여 줍니다.

- 앱이 편집 가능하다고 표시한 속성에는 컨트롤이 있습니다. 텍스트 필드, 드래그할 수 있는 숫자
  필드, 스위치, 불투명도를 포함한 색상 선택기, 열거형을 위한 팝업, 그리고 점, 크기, 사각형,
  인셋, 변환을 위한 성분별 필드입니다.
- 변경은 확정하는 즉시, 또는 드래그하는 동안 계속 전송됩니다. 앱은 레이어의 속성으로
  응답하므로, 다른 속성과 함께 바뀌는 속성(예: 뷰의 alpha와 함께 바뀌는 레이어의 opacity)도
  갱신됩니다.
- ⌘Z는 마지막 변경을 실행 취소하고 ⇧⌘Z는 실행 복귀합니다. 검사가 계속되는 동안 유효합니다.
- 앱이 거부한 변경은 해당 행에 이유가 표시되고, 이전 값으로 돌아갑니다.

변경 후 Cutaway는 그 변경의 영향을 받았을 수 있는 레이어의 스크린샷을 새로 고칩니다.

### 제약 조건

속성 아래에는 뷰의 Auto Layout 제약 조건이 앱이 보고하는 대로 나열됩니다.
`self.leading = Safe Area of UIView.leading + 16` 형태로, 우선순위가 1000 미만이면 우선순위와
함께, 식별자가 있으면 식별자와 함께 표시됩니다. 적용되지 않은 제약 조건은 흐리게 표시되고
표시가 붙으며, UIKit이 생성한 제약 조건은 한 행으로 접힙니다. 제약 조건의 반대편을 클릭하면
그 뷰가 선택됩니다. 미리보기에는 선택한 뷰의 제약 조건의 반대편이 표시됩니다.

### 새로 고침

Cutaway는 요청한 시점에 앱이 어떤 모습이었는지를 보여 줍니다. **새로 고침**(⌘R)은 선택, 펼침
상태, 카메라를 유지한 채 전체 트리와 모든 스크린샷을 다시 요청합니다. **선택한 하위 트리 새로
고침**(⇧⌘R, 행의 컨텍스트 메뉴에도 있음)은 그 레이어의 하위 트리만 요청합니다. 앱이
백그라운드로 가면 Cutaway는 기다립니다. 연결이 끊기면 마지막 화면이 남아 있고, 같은 앱이 다시
발견되면 Cutaway가 다시 연결합니다.

### 아카이브

**아카이브 저장…**(⌘S)은 트리, 아이콘, 그리고 가려진 레이어를 포함한 모든 레이어의 스크린샷,
속성, 제약 조건을 윈도우의 모습과 함께 하나의 `.cutaway` 파일로 모읍니다. 이 파일은
**열기…**(⌘O)로, Finder에서, 또는 Cutaway 아이콘에 떨어뜨려 고유한 윈도우에서 열리며, 편집을
제외한 모든 것이 온라인일 때와 똑같이 동작합니다. 여러 아카이브를 실시간 검사 옆에 동시에
열어 둘 수 있습니다.

**레이어 스크린샷 내보내기…**(⇧⌘E)와 **하위 레이어를 포함한 스크린샷 내보내기…**(⌥⇧⌘E)는
선택한 레이어의 이미지를 기기의 배율로, 투명도를 포함하여, 레이어 자체의 변환과 불투명도는
제외하고 PNG로 씁니다.

### 설정

**설정…**(⌘,)에는 두 페이지가 있습니다. **일반**에서는 언어를 선택합니다. 시스템의 언어이거나
다섯 언어 중 하나입니다. **미리보기**에서는 새로운 검사가 시작되는 방식을 선택합니다. 2D 또는
3D, 레이어 간격, 가려진 레이어와 테두리의 표시 여부입니다. 이미 열려 있는 윈도우는 그대로
유지됩니다.

### 키보드 단축키

| 동작 | 키 |
|---|---|
| 아카이브 열기 | ⌘O |
| 아카이브 저장 | ⌘S |
| 선택한 레이어의 스크린샷 내보내기, 단독 / 하위 레이어 포함 | ⇧⌘E / ⌥⇧⌘E |
| 변경 실행 취소 / 실행 복귀 | ⌘Z / ⇧⌘Z |
| 레이어 목록 필터 | ⌘F |
| 전체 / 선택한 하위 트리 새로 고침 | ⌘R / ⇧⌘R |
| 2D / 3D | ⌘1 / ⌘2 |
| 확대 / 축소 / 보기 재설정 | ⌘= / ⌘- / ⌘0 |
| 가려진 레이어 보기 / 테두리 보기 | ⇧⌘H / ⇧⌘B |
| 선택한 레이어에 초점 맞추기 / 모든 레이어 보기 | ⌥⌘↓ / ⌥⌘↑ |
| 모두 펼치기 / 모두 접기 | ⌥⌘→ / ⌥⌘← |
| 사이드바 / 속성 패널 보기 또는 가리기 | ⌃⌘S / ⌥⌘I |
| 앱 목록 보기 | ⇧⌘0 |
| 설정 | ⌘, |

## 성능

큰 인터페이스도 즉각적으로 느껴져야 합니다. Cutaway는 이를 중심으로 설계되었으며, 테스트
스위트는 실행할 때마다 아래의 수치를 지키는지 검증합니다. 측정은 생성된 앱 형태의 10,000개
레이어 트리(윈도우, 컨테이너, 내비게이션 바, 그리고 아이콘, 레이블, 구분선을 각각 가진 긴 셀
목록)를 대상으로, Debug 빌드에서 이루어집니다.

| 작업 | 한도 |
|---|---|
| 트리 도착 → 목록이 화면에 표시됨 | 2 s |
| 장면 레이아웃 | 1 s |
| 카메라 이동 후 새 프레임 | 16 ms |
| 프레임 하나 그리기 | 16 ms |
| 행 선택 → 미리보기와 속성 패널이 따라감 | 100 ms |
| 목록 검색 | 200 ms |
| 모두 펼치기 / 모두 접기 | 1 s |
| 트리의 아카이브 열기 → 목록이 화면에 표시됨 | 2 s |

이를 달성하는 방법:

- **스크린샷은 압축된 채로 유지됩니다.** 모델은 받은 압축 바이트만 보관합니다. 메인 스레드
  밖에서 압축을 풀어 GPU에 올리고, 픽셀은 버립니다.
- **미리보기는 변화가 있을 때만 그립니다.** 아무것도 움직이지 않는 동안에는 프레임을 제출하지
  않습니다.
- **읽기는 그리기와 보조를 맞춥니다.** 스크린샷이 사용되는 속도보다 빨리 도착하면 Cutaway는
  연결에서 읽기를 멈추고, TCP가 앱에 기다리라고 알립니다. 메모리에 아무것도 쌓이지 않습니다.
- **아무것도 누적되지 않습니다.** 테스트 스위트는 5,000개 레이어에 대해 모든 작업을 열 번
  반복하며 스크린샷, 텍스처, 요청, 윈도우가 하나도 남지 않는지 확인합니다. 더 긴 소크 테스트
  (`scripts/soak.sh`)는 백 회에 걸친 메모리 곡선을 출력합니다.
- **잘못된 데이터로 충돌하지 않습니다.** 모든 프레임은 디코딩 전에 검증되며, 파서는 실행할
  때마다 변형, 절단, 이어 붙이기를 가한 프레임으로 퍼징됩니다.

## Mac에서의 동작

- Cutaway는 2초마다 [CutawayServer](https://github.com/nothingsh/CutawayServer)가 시뮬레이터에서 수신 대기하는 `127.0.0.1`의 48160부터
  48167까지의 포트와, USB로 연결된 각 기기의 같은 포트를 시스템의 `usbmuxd`를 통해 시도합니다.
  핸드셰이크에 응답하는 앱이 목록에 표시됩니다.
- 앱당 연결은 하나이며, 앱이 목록에 있는 동안 유지됩니다. 이미 클라이언트가 있는 앱은
  건드리지 않습니다.
- 10초 동안 한 바이트도 받지 못한 요청은 포기합니다. 앱이 [프로토콜](https://github.com/nothingsh/CutawayProtocol)이 금지하는 것을 보내면
  연결을 닫습니다.
- Cutaway는 그 밖의 네트워크 연결을 만들지 않습니다. 예외는 **업데이트 확인…**을 선택할 때로,
  GitHub에 이 저장소의 릴리스 목록을 요청하며 Mac에 관한 정보는 아무것도 보내지 않습니다.
- 환경설정은 `UserDefaults`에, 최근 아카이브는 시스템의 최근 사용 문서 목록에 있습니다.

## 로드맵

1.0 이후에 계획된 방향으로, [CutawayServer](https://github.com/nothingsh/CutawayServer)와 공유합니다. 순서와 범위는 바뀔 수 있습니다.

- **프로토콜 1.0.** [Cutaway 프로토콜](https://github.com/nothingsh/CutawayProtocol)을 동결하여, 이후의 기능은 프로토콜에 추가만 하도록 합니다.
- **상호작용 분석.** 제스처 인식기와 target–action 쌍을 표시하고, 제스처를 활성화·비활성화하며,
  객체의 메서드를 호출합니다.
- **호스트 앱을 위한 확장 API.** 사용자 정의 속성, 가상 자식 노드, 그리고 기본적으로 접혀 있는
  클래스, 색상 별칭, 이미지에서 제외할 뷰 같은 설정.
- **대규모 계층.** 보이는 레이어만 캡처하는 빠른 모드. 매우 큰 이미지의 분할 전송.
- **더 많은 연결 방식과 플랫폼.** 인증과 암호화를 갖춘 Wi-Fi 연결. tvOS와 visionOS.
- **SwiftUI.** 레이어 트리와 나란히 SwiftUI 뷰의 의미적 계층을 제공합니다.

## FAQ

**내 앱이 목록에 나타나지 않습니다.**
빌드에 [CutawayServer](https://github.com/nothingsh/CutawayServer)가 포함되어 있고(Debug 빌드에만 컴파일됩니다) `CutawayServer.start()`를
호출하는지, 앱이 전면에 있는지, 기기의 경우 케이블로 연결되어 있고 이 Mac을 신뢰하는지
확인하세요. 서버는 48160부터 48167까지 중 처음으로 비어 있는 포트를 사용합니다. Cutaway가
사용할 수 없는 프로토콜 버전의 앱도 목록에 두 버전과 함께 표시됩니다.

**Cutaway에 네트워크가 필요한가요?**
아니요. 시뮬레이터와는 루프백 주소로, 기기와는 USB로 통신합니다. 자체 서버에는 절대 접속하지
않습니다.

**블러, 비디오, Metal 뷰가 비어 있는 이유는 무엇인가요?**
그 콘텐츠는 앱 프로세스 바깥에 있는 시스템의 렌더 서버가 합성하므로, [CutawayServer](https://github.com/nothingsh/CutawayServer)가 레이어
트리에서 렌더링할 수 없습니다.

**기기 없이 앱을 볼 수 있나요?**
기기가 연결되어 있는 동안 아카이브를 저장하고 어디서든 여세요. 개발 용도로는 테스트 지원
라이브러리가 아카이브를 시뮬레이터의 앱처럼 재생할 수도 있습니다(`scripts/replay.sh`).

**검사하면 앱이 바뀌나요?**
직접 한 편집만 앱을 바꿉니다. 캡처는 건드린 모든 것을 복원하며, 속성을 읽어도 레이아웃은
일어나지 않습니다. [CutawayServer](https://github.com/nothingsh/CutawayServer)의 README를 참조하세요.

<a id="development"></a>
## 개발

Cutaway는 AppKit과 Metal을 사용하여 Swift 6로 작성되었습니다. 코드는 로컬 Swift 패키지
`CutawayKit`에 있으며, 앱 타깃은 이를 조립하는 일만 합니다.

| 타깃 | 내용 |
|---|---|
| `CutawayWire` | 프레임, 값 타입으로 된 프로토콜의 메시지, 아카이브 형식 |
| `CutawayTransport` | 앱 찾기, `usbmuxd`, 세션과 요청 |
| `CutawayModel` | 레이어 트리, 스크린샷과 속성, 윈도우들이 공유하는 상태 |
| `CutawayScene` | 각 레이어를 어디에 어떤 순서로 그릴지, 그리고 히트 테스트. 순수 Swift |
| `CutawayRender` | Metal로 장면 그리기 |
| `CutawayUI` | 윈도우, 목록, 미리보기, 속성 패널, 설정 |
| `CutawayTestSupport` | 프로토콜의 픽스처를 재생하는 모의 서버, 합성 트리, 가짜 `usbmuxd` |

와이어 형식은 [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol)에 정의되어 있으며,
`Protocol/`에 서브모듈로 체크아웃됩니다. 그 Swift 코드는 스키마에서 생성되어 체크인되어
있습니다. [CutawayServer](https://github.com/nothingsh/CutawayServer)와 공유하는 것은 프로토콜뿐입니다.

클론한 뒤 `./setup.sh`를 한 번 실행하세요. 프로토콜 서브모듈을 체크아웃하고, Xcode, XcodeGen,
jq가 있는지 확인하고, 버전이 고정된 도구를 `.tools/`에 설치하고, git 훅을 설정하고,
`project.yml`에서 `Cutaway.xcodeproj`를 생성합니다. 다시 실행해도 문제가 없습니다.

| 작업 | 명령 |
|---|---|
| CI와 같은 방식으로 빌드하고 테스트 (코드만 필요) | `scripts/check.sh` |
| 패키지만 테스트 | `cd CutawayKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme CutawayKit-Package -destination 'platform=macOS' -testLanguage en` |
| 포맷한 뒤 린트 | `scripts/format.sh` |
| 실행 중인 Cutaway를 위해 아카이브를 시뮬레이터의 앱처럼 제공 | `scripts/replay.sh <file.cutaway>` |
| 모든 작업을 백 회 반복하고 메모리 곡선 출력 | `scripts/soak.sh` |

- 눈으로 판단하는 것은 없습니다. 장면 계층은 단위 테스트로 검증하고, 그리기 계층은
  오프스크린으로 렌더링하여 `Baselines/`의 기준 이미지와 비교합니다.
- 테스트에는 기기가 전혀 필요 없습니다. 연결은 이 Mac에서 프로토콜의 픽스처를 재생하는 모의
  서버를 대상으로 테스트합니다.

## 라이선스

Cutaway는 자유 소프트웨어이며, GNU General Public License v3.0으로 배포됩니다.
[LICENSE](../../LICENSE)를 참조하세요. [FlatBuffers](https://github.com/google/flatbuffers)(Apache
License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit)(MIT),
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine)(MIT)으로 만들어졌으며,
이들의 라이선스는 ‘Cutaway에 관하여’ 패널과
[`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements)에 있습니다.
[Cutaway 프로토콜](https://github.com/nothingsh/CutawayProtocol)은 MIT 라이선스를 따릅니다.
