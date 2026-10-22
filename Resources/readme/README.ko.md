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
    <img src="overview-light.png" alt="Cutaway가 앱을 3D로 검사하는 모습: 레이어 트리, 벌려 놓은 레이어, 선택한 레이어의 속성." width="850">
  </picture>
</p>

<a id="features"></a>
## 기능

- **인터페이스가 어떻게 만들어졌는지 봅니다.** 모든 윈도우의 레이어 트리와 함께 뷰 컨트롤러, 각 뷰를 보유한 멤버 변수를 표시합니다. [레이어 목록](https://nothingsh.github.io/Cutaway/guide/hierarchy)
- **3D로 분해해 봅니다.** 모든 레이어의 스크린샷을 2D로 평평하게, 또는 3D로 떨어뜨려 보여 줍니다. 회전, 확대/축소, 간격 조절이 가능합니다. [미리보기](https://nothingsh.github.io/Cutaway/guide/preview)
- **측정합니다.** ⌥를 누른 채 다른 레이어(미리보기 또는 목록)를 가리키면 포인트 단위의 거리가 보입니다. [측정](https://nothingsh.github.io/Cutaway/guide/measuring)
- **실행 중에 바꿉니다.** 속성을 편집하면 실행 중인 앱에 바로 적용되고, ⌘Z로 되돌릴 수 있습니다. [속성](https://nothingsh.github.io/Cutaway/guide/attributes)
- **제약 조건을 따라갑니다.** 뷰의 모든 Auto Layout 제약 조건과 적용되지 않는 것, 그리고 반대쪽 끝을 보여 줍니다. [제약 조건](https://nothingsh.github.io/Cutaway/guide/constraints)
- **다크 모드와 큰 텍스트를 시험합니다.** 앱의 외관, 텍스트 크기, 레이아웃 방향, 크기 클래스를 재정의합니다. [환경](https://nothingsh.github.io/Cutaway/guide/environment)
- **코드로 이동합니다.** Xcode에서 클래스를 열고, 에셋과 String Catalog의 이름을 보고, LLDB 명령을 복사합니다. [소스 코드](https://nothingsh.github.io/Cutaway/guide/source)
- **발견한 것을 남깁니다.** 검사를 아카이브로 저장해 기기 없이 어느 Mac에서나 열고, 레이어를 PNG로 내보냅니다. [아카이브와 내보내기](https://nothingsh.github.io/Cutaway/guide/archives)

Cutaway는 이 Mac의 앱, 그리고 USB 케이블로 연결된 앱하고만 통신합니다. 분석도, 충돌 보고도 없습니다.
영어, 중국어 간체, 중국어 번체, 일본어, 한국어로 제공됩니다.

<a id="requirements"></a>
## 요구 사항

- macOS 14 이상. Metal을 지원하는 GPU가 있는 Mac (macOS 14를 실행하는 모든 Mac).
- [CutawayServer](https://github.com/nothingsh/CutawayServer)를 포함한 앱이 iOS Simulator에서,
  또는 USB로 Mac에 연결된 iPhone이나 iPad에서 실행 중이어야 합니다.

<a id="installation"></a>
## 설치

[Releases](https://github.com/nothingsh/Cutaway/releases) 페이지에서 `Cutaway-<버전>.dmg`를 다운로드해 열고, Cutaway를
응용 프로그램 폴더로 드래그하세요. Cutaway는 오픈 소스이며 빌드는 Apple의 공증을 받지 않았습니다.
그래서 처음 열 때 macOS가 개발자를 확인할 수 없다고 알립니다. **시스템 설정 › 개인정보 보호 및
보안**을 열고 **그래도 열기**를 선택하거나, 다음을 실행하세요.

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › 업데이트 확인…**으로 더 새로운 릴리스가 나왔는지 확인할 수 있습니다.

## 빠른 시작

1. iOS 앱에 [CutawayServer](https://github.com/nothingsh/CutawayServer)를 추가하고 시작 시 `CutawayServer.start()`를 한 번 호출합니다. Debug
   빌드에만 컴파일됩니다.
2. 시뮬레이터에서, 또는 케이블로 Mac에 연결된 기기에서 앱을 실행합니다.
3. Cutaway를 엽니다. 몇 초 안에 앱이 목록에 나타납니다. 선택하세요.

모든 단계와 UIKit, SwiftUI용 코드, 앱이 나타나지 않을 때 확인할 것은 [시작하기 가이드](https://nothingsh.github.io/Cutaway/guide/getting-started)에 있습니다.

<a id="documentation"></a>
## 문서

나머지는 모두 [Cutaway 웹사이트](https://nothingsh.github.io/Cutaway/)에 있습니다(현재 영어와 중국어 간체만 제공).

- [가이드](https://nothingsh.github.io/Cutaway/guide/getting-started): 작업별 Cutaway 사용법과 모든 [키보드 단축키](https://nothingsh.github.io/Cutaway/guide/shortcuts).
- [통합](https://nothingsh.github.io/Cutaway/integrate/): 앱에 CutawayServer 추가하기, Debug와 Release 빌드, 앱 고유의 정보 표시하기.
- [프로토콜](https://nothingsh.github.io/Cutaway/protocol/): Cutaway와 CutawayServer가 통신하는 방법과 함께 쓸 수 있는 버전.
- [FAQ와 문제 해결](https://nothingsh.github.io/Cutaway/resources/faq), [개인정보 보호와 보안](https://nothingsh.github.io/Cutaway/resources/privacy), [성능](https://nothingsh.github.io/Cutaway/resources/performance), [릴리스 노트](https://nothingsh.github.io/Cutaway/resources/releases), [로드맵](https://nothingsh.github.io/Cutaway/resources/roadmap).

<a id="development"></a>
## 개발

Cutaway를 빌드하고 테스트하는 방법과 변경 사항을 검토하는 방식은 [CONTRIBUTING.md](../../CONTRIBUTING.md)에 있습니다.
세 저장소가 어떻게 맞물리는지는 웹사이트의 [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) 페이지에서 설명합니다.

## 라이선스

Cutaway는 자유 소프트웨어이며, GNU General Public License v3.0으로 배포됩니다.
[LICENSE](../../LICENSE)를 참조하세요. [FlatBuffers](https://github.com/google/flatbuffers)(Apache
License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit)(MIT),
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine)(MIT)으로 만들어졌으며,
이들의 라이선스는 ‘Cutaway에 관하여’ 패널과
[`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements)에 있습니다.
[Cutaway 프로토콜](https://github.com/nothingsh/CutawayProtocol)은 MIT 라이선스를 따릅니다.
