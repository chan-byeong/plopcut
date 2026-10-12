# Notedrop (한국어)

[English README](README.md)

Notedrop은 로컬 우선(local-first) macOS 클립보드 앱입니다. 선택한 텍스트나 클립보드 이미지를 사용자가 직접 캡처하고,
노트와 태그를 붙여 라이브러리에서 다시 찾습니다. 모든 드롭은 Mac에 일반적인 읽을 수 있는 파일로 저장됩니다.

Notedrop은 백그라운드에서 클립보드를 감시하지 않습니다. 사용자가 캡처를 요청할 때만 클립보드나 선택한 텍스트를 읽습니다.

> 상태: 출시 전입니다. 다운로드와 서명에 관한 내용은 출시 시 `docs/release.md`에 정리될 예정입니다(준비 중).

## 할 수 있는 일

- **선택한 텍스트 캡처**: 전역 단축키(기본값 `Shift`+`Command`+`C`)를 누릅니다. 단축키는 설정에서 바꿀 수 있습니다.
- **클립보드 저장**: 메뉴 막대 항목의 `Save Clipboard...`를 사용합니다.
- **노트와 태그 추가**: 저장 팝업에서 입력합니다. 설정에서 텍스트를 팝업 없이 바로 저장하도록 고를 수도 있습니다.
- **라이브러리 둘러보기**: 검색하고, 유형·태그·앱·기간으로 거르고, 드롭을 열어 제목, 노트, 태그를 편집합니다.
- **출처 열기, 내용 복사, Markdown 내보내기, 휴지통 이동**: 드롭의 출처(예: Chrome 페이지 URL)를 열거나 내용을 복사할 수 있습니다.

## 설치

요구 사항: macOS가 설치된 Mac. 지원하는 최소 macOS 버전은 아직 확정되지 않았습니다
([docs/update-method.md](docs/update-method.md#open-decisions) 참고).

1. 릴리스 페이지에서 `Notedrop.dmg`를 내려받습니다. *링크: 첫 릴리스와 함께 공개 예정(`docs/release.md`, 준비 중 참고).*
2. 디스크 이미지를 열고 **Notedrop**을 **응용 프로그램(Applications)** 폴더로 끌어 놓습니다.
3. 응용 프로그램에서 Notedrop을 엽니다.

## 첫 실행

처음 실행하면 드롭을 어디에 저장할지 묻습니다.

- **기본 폴더 사용**: `~/Documents/Notedrop`
- **다른 폴더 선택**

둘 중 하나를 확정할 때까지 대화상자가 남습니다. 나중에 설정에서 폴더를 바꾸면 새로 만드는 드롭부터 적용됩니다.
기존 드롭은 옮기거나 복사하지 않습니다.

## 권한

Notedrop은 해당 기능이 필요할 때만 권한을 요청합니다. 설정 화면에서 권한 상태를 확인할 수 있습니다.

| 권한 | 허용 위치 | 필요한 이유 |
| --- | --- | --- |
| 손쉬운 사용(Accessibility) | 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용 | 사용 중인 앱에서 선택한 텍스트를 읽고, 직접 읽기가 안 될 때 대신 `Command`+`C`를 보내 복사합니다. 이 권한이 없으면 선택 텍스트 캡처가 동작하지 않습니다. |
| 자동화(Google Chrome) | 시스템 설정 › 개인정보 보호 및 보안 › 자동화 | Chrome 활성 탭의 URL을 읽어 드롭의 출처 링크를 남깁니다. macOS가 처음 한 번 묻습니다. 허용하지 않아도 캡처는 되지만 URL은 저장되지 않습니다. |
| 클립보드 | Notedrop 설정 항목 없음. 최근 macOS는 앱이 클립보드를 읽을 때 자체 확인 창을 띄울 수 있습니다. | `Save Clipboard...`를 실행할 때만 클립보드를 읽습니다. |

## 데이터 저장 위치

- **드롭**: `~/Documents/Notedrop/drops/<드롭 ID>/` 폴더 하나당 드롭 하나입니다. 안에는 `drop.json`(메타데이터),
  `content.md` 또는 `image.png`, `note.md`가 있습니다. 텍스트 편집기나 Finder로 열어 볼 수 있습니다.
- **설정**: `~/Library/Application Support/Notedrop/settings.json`

Notedrop은 데이터베이스를 사용하지 않으며, 이 파일을 외부로 보내지 않습니다. 자세한 내용은 [docs/privacy.md](docs/privacy.md)를 참고하세요.

## 삭제(제거) 방법

1. Notedrop을 종료합니다.
2. 응용 프로그램의 **Notedrop.app**을 휴지통으로 옮깁니다.
3. 선택 사항: 설정 폴더 `~/Library/Application Support/Notedrop`을 삭제합니다.
4. 선택 사항: `~/Documents/Notedrop`의 저장된 드롭을 삭제합니다. **드롭이 모두 삭제됩니다.** 보관하려면 먼저 다른 곳에 복사하세요.
   앱을 삭제해도 드롭은 자동으로 지워지지 않습니다.
5. 선택 사항: 시스템 설정 › 개인정보 보호 및 보안의 **손쉬운 사용**과 **자동화**에서 Notedrop 항목을 지웁니다.

## 개인정보

모든 드롭과 설정은 사용자의 Mac에만 남습니다. Notedrop은 데이터를 외부로 보내지 않으며 원격 측정(telemetry)을 포함하지 않습니다.
근거와 세부 내용은 [docs/privacy.md](docs/privacy.md)를 참고하세요.

## 이번 릴리스에서 제외된 기능

데이터베이스 저장, 클라우드 동기화, OCR, AI 기능, 협업, 모바일 앱, 백그라운드 클립보드 감시, 전체 화면 녹화,
상시 하이라이트 오버레이, 원문 위치의 완벽한 복원은 의도적으로 제외되었습니다. 자세한 내용은
[docs/release-scope.md](docs/release-scope.md)를 참고하세요.

## 업데이트

이번 릴리스에는 자동 업데이트 확인 기능이 없습니다. 새 버전은 직접 내려받아 설치합니다.
이는 제안된 기본값이며 소유자의 확인이 필요합니다. [docs/update-method.md](docs/update-method.md)를 참고하세요.

## 라이선스

**라이선스: 미정(자리표시자).** 아직 라이선스를 정하지 않았습니다. 정해질 때까지 모든 권리는 저작자에게 있습니다.
미결정 사항은 [docs/update-method.md](docs/update-method.md#open-decisions)에 있습니다.

---

## 기여자용 안내

Swift(SwiftUI, AppKit)로 새로 구현한 버전입니다. 이전 Tauri + React 버전은 `legacy/tauri` 브랜치와 `tauri-final` 태그에
동작 참고용으로만 보존되어 있습니다.

먼저 [`AGENTS.md`](AGENTS.md)를 읽고, [구현 사양](docs/swift-migration/spec.md)과
[동작 체크리스트](docs/swift-migration/behavior-checklist.md)를 확인하세요. `scripts/make-app.sh`로 개발용 `Notedrop.app`을 만들 수 있습니다.
