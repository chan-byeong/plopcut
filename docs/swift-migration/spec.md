# Notedrop Swift 구현 사양

Linear: [STA-39](https://linear.app/byeoung/issue/STA-39)

이 문서는 Tauri + React로 만든 Notedrop을 Swift(SwiftUI/AppKit)로 **새로 구현**하기 위한 스택 중립 사양입니다. 구현자는 레거시
코드를 번역하지 않고 이 문서와 [동작 체크리스트](behavior-checklist.md), [픽스처](fixtures/README.md)만으로 구현할 수 있어야
합니다. 레거시 구현은 `legacy/tauri` 브랜치와 `tauri-final` 태그에 보존되어 있으며, 문서에 명시한 파일만 참고합니다.

## 읽는 순서와 범위

1. 이 문서: 무엇을 만들지.
2. [동작 체크리스트](behavior-checklist.md): 코드에만 남아 있는 세부 동작과 확인 방법.
3. [Design.md](../../Design.md), [design-system.md](../design-system.md): 시각 기준. 두 문서의 "구현 경계"와 AppKit
   도구 막대 설명은 Tauri 구조를 전제로 하므로 무시합니다. 레이아웃 수치, 색상·재질 토큰, 컴포넌트 상태, 접근성, 검증 기준만
   따릅니다. 기준 이미지는 [`docs/design/sta30-font-book/`](../design/sta30-font-book/README.md)와
   `docs/design/library-sidebar-*.png`입니다.
4. 문구는 [strings.md](strings.md)의 `en`·`ko` 표가 유일한 원본입니다. 레거시 사전에서 그대로 추출한 것입니다.

이 브랜치에는 레거시 코드가 없습니다. 동작이 모호할 때만 `git show legacy/tauri:<경로>`로 파일 하나씩 확인합니다. 읽을 필요가
없는 레거시: `src/**/*.tsx`의 컴포넌트 구현, `src/App.css`, `src-tauri/src/native_toolbar.rs`, `src-tauri/src/sf_symbols.rs`.

### 범위 밖

[`AGENTS.md`](../../AGENTS.md)의 제품 경계를 그대로 유지합니다. 데이터베이스, 클라우드 동기화, OCR, AI, 협업, 모바일,
지속적 클립보드 감시, 전체 화면 녹화, 상시 하이라이트 오버레이, 원문 위치의 완벽한 복원은 명시적 요청 없이 만들지 않습니다.
클립보드는 사용자가 단축키나 메뉴로 요청했을 때만 읽습니다.

### 플랫폼

macOS 13 이상(레거시 번들의 `minimumSystemVersion`). Apple Silicon과 Intel을 모두 지원합니다. 앱 이름은 `Notedrop`,
레거시 번들 ID는 `app.notedrop.dev`입니다. 번들 ID를 바꾸면 사용자는 손쉬운 사용·자동화 권한을 다시 허용해야 합니다.

## 용어

| 용어 | 정의 |
| --- | --- |
| Drop | 저장한 텍스트 또는 이미지 한 건. 디스크의 폴더 하나. |
| Library | Drop을 검색하고 검토하는 메인 창 영역. |
| Collection | 사이드바에서 고르는 보기. 유형(라이브러리=전체, 텍스트, 이미지) 또는 태그. |
| Source | Drop을 가져온 앱·윈도우 제목·URL·파일 경로. 모두 선택 값. |
| Note | 사용자가 Drop에 붙이는 메모. |
| Tag | 소문자로 정규화한 사용자 키워드. |
| Save Popup | 저장 전에 노트와 태그를 입력하는 별도 창. |
| Draft | 캡처했지만 아직 저장하지 않은 내용. |
| Inspector | Library 오른쪽의 정보 패널(노트, 태그, 출처). |

## 1. 데이터와 저장 형식 (호환성 계약)

기존 사용자의 Drop 폴더와 `settings.json`을 **수정 없이 읽고 계속 쓸 수 있어야 합니다.** 이 장의 형식은 바꾸지 않습니다.
실제 파일 모양은 [픽스처](fixtures/README.md)를 기준으로 확인합니다.

### 1.1 폴더 구조

```text
{storageFolder}/                 기본값 ~/Documents/Notedrop
  drops/
    {dropId}/
      drop.json                  메타데이터
      content.md                 텍스트 Drop의 본문
      image.png                  이미지 Drop의 이미지
      note.md                    노트 (항상 생성, 비어 있을 수 있음)
```

- 텍스트 Drop: `drop.json`, `content.md`, `note.md`.
- 이미지 Drop: `drop.json`, `image.png`, `note.md`.
- `drops/` 아래의 폴더가 아닌 항목(`.DS_Store` 등)은 무시합니다.
- 원본 데이터는 읽을 수 있는 파일이어야 합니다. 데이터베이스를 쓰지 않습니다.

### 1.2 `drop.json`

UTF-8, 들여쓰기 2칸의 pretty JSON, 키는 camelCase입니다.

| 키 | 타입 | 규칙 |
| --- | --- | --- |
| `id` | string | 폴더 이름과 같음. |
| `type` | `"text"` \| `"image"` | 저장하는 값은 이 둘뿐. 읽을 때 `"mixed"`를 만나도 깨지지 않아야 합니다(체크리스트 D-02). |
| `title` | string | 비어 있지 않음. |
| `text` | string \| null | **항상 `null`로 저장**합니다. 본문은 `content.md`에 있습니다. |
| `imagePath` | string \| null | 텍스트 Drop은 `null`, 이미지 Drop은 `"image.png"`. |
| `source` | object | 아래 참조. 항상 객체. |
| `note` | string \| null | **항상 `null`로 저장**합니다. 노트는 `note.md`에 있습니다. |
| `tags` | string[] | 정규화된 태그. |
| `createdAt` | string | 아래 시각 형식. 저장 후 바뀌지 않음. |
| `updatedAt` | string | 수정할 때마다 갱신. |

`source`의 키는 `appName`, `windowTitle`, `url`, `filePath`이며 모두 string \| null입니다. 저장할 때는 네 키를 모두
쓰고 값이 없으면 `null`입니다.

읽을 때는 누락된 키를 모두 허용해야 합니다. 필수는 `id`, `type`, `title`, `createdAt`, `updatedAt`뿐입니다. `source`가
없으면 빈 source, `tags`가 없으면 빈 배열로 취급합니다. 알 수 없는 키는 무시하되, 이 앱이 파일을 다시 쓸 때 보존할 필요는
없습니다.

### 1.3 본문, 이미지, 노트

- `content.md`: 텍스트 그대로. 저장 전에 **끝의 `\r`, `\n`만** 제거합니다. 앞쪽 공백과 중간 줄바꿈은 유지합니다.
- `note.md`: 노트 원문. 비었거나 공백뿐이면 화면에서는 "노트 없음"으로 취급합니다. 노트를 수정하면 파일을 항상 덮어씁니다.
- `image.png`: 클립보드 이미지를 PNG로 변환한 바이트. 이미지 Drop은 `imagePath`가 없어도 `image.png`를 기본 경로로 봅니다.
- 읽는 중 파일 하나를 못 읽어도 Drop 전체를 버리지 않고 경고(1.7)를 남깁니다.

### 1.4 ID, 시각, 제목

- 시각 형식: UTC, 소수 9자리. `createdAt`은 `2026-10-02T06:31:29.850365000Z`.
- ID: `{YYYY-MM-DD}_{HHMMSS}_{나노초 9자리}_{slug}`. 예: `2026-10-02_063129_850365000_cursor`.
  같은 ID의 폴더가 있으면 `-2`, `-3`을 이어 붙입니다.
- slug: 제목을 소문자로 바꾸고 ASCII 영숫자만 남깁니다. 그 밖의 문자 묶음은 `-` 하나로 바꾸고, 앞쪽 `-`는 쓰지 않습니다.
  48자에 도달하면 멈추고 양끝의 `-`를 제거합니다. 결과가 비면 `drop`입니다. 한글 제목은 모두 `drop`이 됩니다.
- 제목 추론(첫 번째로 비어 있지 않은 값, 앞뒤 공백 제거, 최대 80자):
  명시한 제목 → 윈도우 제목 → 앱 이름 → 본문의 첫 비어 있지 않은 줄 → `Untitled Drop`.
  이미지는 본문 대신 `Image Drop`을 쓰고, 클립보드 캡처에서 텍스트가 없으면 `{type} Drop`을 씁니다.
- 폴더 이름과 ID에 `/`, `\`, `..`가 들어 있거나 비어 있는 ID는 거부합니다.

### 1.5 태그

- 입력은 쉼표로 나눕니다. 각 항목은 앞뒤 공백을 지우고, 앞쪽 `#`을 모두 지우고, 소문자로 바꿉니다.
- 빈 항목과 중복(먼저 나온 것 유지)을 제거합니다. 순서를 유지합니다.
- 디스크에서 읽을 때도 같은 규칙으로 다시 정규화합니다.
- 최근 태그: 정규화한 목록 최대 12개. 저장 후 `새 Drop의 태그 + 기존 최근 태그` 순서로 합쳐 중복을 제거하고 12개로 자릅니다.

### 1.6 목록 읽기, 검색, 정렬

- 앱 시작 시 `drops/`를 스캔해 메모리에 올립니다. 저장 후, 인스펙터 편집 후, 새로고침 동작, 다른 곳에서 저장했다는 신호를 받으면
  갱신합니다. 파일 감시는 필수가 아닙니다.
- 정렬: `createdAt` 내림차순(문자열 비교), 같으면 `id` 내림차순.
- 검색: 질의를 소문자로 바꾸고 앞뒤 공백을 지웁니다. 비면 전체. 아니면 제목, 본문, 노트, 이미지 경로, 앱 이름, 윈도우 제목,
  URL, 각 태그 중 하나에 **부분 문자열**로 들어 있으면 일치합니다(대소문자 무시).
- 유형 필터: 전체/텍스트/이미지. 태그 필터: 정확히 일치. 앱 필터: 정확히 일치. 기간: 전체, 오늘(같은 달력 날짜), 최근 7일,
  최근 30일(`createdAt ≥ 지금 − N일`). 필터는 AND로 결합하고 검색어와도 AND입니다.
- 날짜 그룹(달력 날짜 기준): 오늘, 어제, 지난 7일(2~7일 전), 이전. 빈 그룹은 숨깁니다.
- 선택한 Drop이 필터 결과에 없으면 결과의 첫 항목을 선택합니다. 결과가 비면 선택 없음.

### 1.7 스캔 경고

폴더 하나가 깨져도 목록은 계속 만들고 경고만 모읍니다.

| 코드 | 상황 |
| --- | --- |
| `drop_scan_skipped` | 항목을 읽지 못함, `drop.json`을 읽지 못함 또는 JSON이 잘못됨. 그 Drop은 건너뜀. |
| `drop_content_unreadable` | `content.md`를 못 읽음. |
| `drop_image_unreadable` | 이미지를 못 읽음. |
| `drop_note_unreadable` | `note.md`를 못 읽음. |

`drops/`가 없으면 빈 목록입니다. `drops/` 자체를 읽지 못하면 오류(`storage_unreadable`)입니다.

### 1.8 `settings.json`

경로: `~/Library/Application Support/Notedrop/settings.json` (저장 폴더 설정과 무관한 고정 위치).

| 키 | 타입 | 기본값 / 규칙 |
| --- | --- | --- |
| `storageFolderPath` | string | 기본 `~/Documents/Notedrop`의 절대 경로. 공백뿐이면 거부(저장 시) 또는 기본값(읽을 때). |
| `hasCompletedFirstRun` | bool | 기본 `false`. |
| `theme` | `"system"` \| `"light"` \| `"dark"` | 기본 `system`. 읽을 때 잘못된 값은 `system`으로 보정. |
| `captureConfirmationMode` | `"modal"` \| `"instant"` | 기본 `modal`. 키가 없으면 `modal`. 읽을 때 잘못된 값은 오류. |
| `selectedTextShortcut` | string | 기본 `"Shift+Cmd+C"`. 비어 있으면 기본값. |
| `paneWidths` | `{sidebar, library}` | 기본 `{220, 330}`. 읽고 쓸 때 `sidebar`는 180–320, `library`는 300–560으로 고정. |
| `recentTags` | string[] | 기본 `[]`. 읽고 쓸 때 태그 규칙(1.5)과 최대 12개. |
| `updatedAt` | string | 저장할 때마다 갱신(1.4의 시각 형식). |

- 파일이 없으면 기본값으로 만들고 저장합니다. JSON이 잘못되면 `settings_invalid` 오류입니다. 필수 키는 `storageFolderPath`,
  `hasCompletedFirstRun`, `theme`, `updatedAt`이며 나머지는 누락을 허용하고 기본값을 씁니다.
- 쓸 때는 임시 파일에 쓰고 동기화한 뒤 이름을 바꾸는 방식으로 원자적으로 교체하고, 동시 갱신은 직렬화합니다.
- 부분 갱신: 보낸 필드만 바꾸고 나머지는 유지합니다. 검증에 실패하면 파일을 건드리지 않습니다.
- `selectedTextShortcut`은 Tauri 문법의 문자열(`Shift+Cmd+C`)로 저장합니다. 호환을 위해 이 문자열 형식을 유지하고 Swift 쪽에서
  해석합니다(체크리스트 C-06).

## 2. 앱 구조

### 2.1 창과 진입점

| 요소 | 사양 |
| --- | --- |
| 메인 창 | 기본 1120×720, 최소 960×640. 제목 표시줄 투명, 앱 이름 제목 없음, 통합 도구 막대. Library와 Settings를 한 창에서 전환. |
| Save Popup 창 | 430×560, 크기 조절 불가, 항상 위, 화면 중앙, Dock·전환기에 노출하지 않음, 제목 숨김, 닫으면 Draft 폐기. |
| 메뉴 막대 항목 | 템플릿 아이콘, 툴팁 `Notedrop`. 좌클릭: 메인 창 열기와 포커스. 메뉴: `Save Clipboard...`(별도 창 팝업 또는 `instant`), `Open Library`. |
| 메뉴 막대 피드백 | 저장 성공 `Saved`, 실패 `Error`를 아이콘 옆 제목으로 900 ms 표시하고 툴팁도 같이 바꾼 뒤 원래대로 복원. |
| 전역 단축키 | 선택 텍스트 캡처 하나. 기본 `Shift+Cmd+C`. 설정에서 바꿈. |

앱은 메뉴 막대 항목과 전역 단축키로 사용하므로 메인 창이 닫혀 있어도 캡처가 동작해야 합니다. 창을 닫았을 때 앱이 종료되는지는
레거시에서 확인하지 못했습니다(체크리스트 D-07).

### 2.2 메인 창 레이아웃

네 영역: 사이드바, 목록, 본문, 인스펙터. 수치는 [design-system.md](../design-system.md)의 "레이아웃 및 간격"과 "반응형
레이아웃 및 패널 상태"를 따릅니다. 핵심 규칙:

- 사이드바 기본 220, 목록 기본 330, 인스펙터 280, 본문 최소 360. 사이드바는 창 가장자리에 붙이지 않고 8 pt 인셋과 둥근
  모서리를 가집니다. 본문은 불투명 바탕입니다.
- 사용자가 사이드바를 접기 전까지 항상 펼쳐 둡니다. 접힘 상태는 창 크기 변경과 Library/Settings 전환을 거쳐도 유지합니다
  (영구 저장하지 않음). 두 화면에서 사이드바 너비와 모양이 같습니다.
- 인스펙터는 공간이 충분하면(기본 사이드바에서 콘텐츠 폭 1176 이상) 본문 옆에 둡니다. 부족하면 접고, 토글로 오른쪽
  오버레이로 엽니다. 같은 토글이나 Escape로 닫고 Drop 목록에 포커스를 돌려줍니다(D-13). 사용자가 옆에 있는 인스펙터를 직접 접으면 그
  선택을 유지합니다.
- 구분선은 드래그로 조절하고(키보드 조절 없음, D-14), 표시 중인 실제 너비를 접근성 값으로 알립니다. 창 크기 때문에 줄어든
  표시 너비로 저장된 `paneWidths`를 덮어쓰지 않습니다. 사용자가 직접 조절했을 때만 저장합니다.
- 패널을 접거나 창 크기를 바꿔도 선택한 Drop, 검색어, 필터, 노트·태그 편집 초안은 유지합니다.

### 2.3 도구 막대

왼쪽부터 창 제어, 사이드바 토글, (공간), 새로고침, 인스펙터 토글, **선택한 텍스트 캡처**(파란 캡슐, 아이콘+문구), 검색,
설정(Library↔Settings 전환; Settings에서는 Library 아이콘). 개별 컨트롤은 동일한 높이와 세로 중앙 정렬을 가집니다.

- 사이드바 토글은 사이드바가 펼쳐져 있을 때 사이드바 오른쪽 끝에 맞추고, 접으면 창 제어 옆으로 옮깁니다. Library와
  Settings 모두에서 동작합니다.
- 인스펙터 토글과 검색은 Library에서만 활성입니다.
- 검색: 콘텐츠 폭이 1050 pt 이상이면 입력 필드, 미만이면 아이콘. 아이콘 클릭 또는 `Cmd+F`로 필드를 열고 포커스합니다.
  Escape는 필드를 닫지만 검색어와 결과는 유지합니다. 지우기 버튼은 검색어를 비우고 전체 결과를 복원합니다. 인스펙터 오버레이와
  검색이 함께 열려 있으면 Escape가 검색을 먼저 닫고 다음 Escape가 인스펙터를 닫습니다.
- 모든 도구 막대 컨트롤은 접근성 레이블과 도움말을 가집니다(문구는 `i18n.tsx`의 `refreshLibrary`, `captureSelected`,
  `showSidebar`/`hideSidebar`, `showInspector`/`hideInspector`, `sidebarPanelHelp`, `inspectorPanelHelp`).

### 2.4 사이드바

- 섹션 `보관함`: 라이브러리(전체), 텍스트, 이미지. 각 행은 개수를 오른쪽에 표시합니다.
- 섹션 `태그`: 모든 Drop의 태그를 정렬해 한 행씩. 없으면 `태그 없음`.
- 아래 고정: `설정`.
- **선택 행은 항상 정확히 하나**입니다: 유형 행, 태그 행, 설정 행 중 하나. 유형 행을 고르면 태그 필터를 지우고, 태그 행을 고르면
  유형을 `all`로 돌립니다. 같은 태그를 다시 눌러도 선택을 유지합니다. 설정 화면에서는 설정 행만 선택됩니다.
- 창이 활성이면 선택 행은 파란색, 비활성이면 중성색입니다. 도구 막대 검색에 포커스가 가도 창 활성 상태로 취급해 색이 바뀌지
  않아야 합니다.
- 행은 모두 같은 높이(32)와 같은 열 구조(아이콘, 레이블, 개수)를 씁니다. 섹션 제목은 아이콘 없는 작은 글씨입니다.

### 2.5 목록

- 헤더: 컬렉션 이름(`라이브러리`/`텍스트`/`이미지`/태그 이름)과 아래에 `{n}개의 드롭`. 오른쪽에 필터 버튼, 필터가 걸려 있을
  때만 필터 지우기 버튼. 필터는 **앱**과 **기간**만 다룹니다(유형·태그는 사이드바 담당). 적용된 필터는 헤더 아래에
  지울 수 있는 칩으로 표시하고 줄바꿈합니다. 필터 지우기는 사이드바 선택을 유지합니다.
- 날짜 그룹 제목(`오늘`, `어제`, `지난 7일`, `이전`)과 행. 행: 출처 앱 아이콘(없으면 공통 아이콘), 제목, 시각(시:분), 미리보기
  한 줄(본문 → 노트 → 윈도우 제목 → URL → 이미지 경로 → 앱 이름 → 모두 없으면 `No preview`. 이 문구는 레거시에서 영어로 고정), 앱 이름, 태그 최대 3개와 `+n`.
- 로딩, 결과 없음(`noMatches`), Drop 없음(`noDrops`), 스캔 경고를 서로 구분해 표시합니다.
- 키보드: 위/아래 화살표로 선택 이동(경계에서 멈춤), Enter로 제목 입력에 포커스, Escape로 목록에 포커스, `Cmd+Backspace`로
  삭제 확인, 우클릭 메뉴(출처 열기(URL이 있을 때), 내용 복사(텍스트일 때), Markdown 내보내기, 휴지통으로 이동).
- 목록에 포커스가 없을 때 선택 행은 중성색으로 약해집니다(AppKit 테이블 동작). STA-38에서 도입했고 실제 앱에서는 확인하지
  못했습니다.

### 2.6 본문

- 상단: 유형 표시(`텍스트 드롭`/`이미지 드롭`), 제목 입력, 동작 버튼 `출처 열기`(URL 없으면 비활성), `Markdown 내보내기`,
  `휴지통으로 이동`.
- 제목은 항상 보이는 인라인 이름 변경 필드입니다. 글자 위치는 고정이고 편집할 때만 필드 모양이 나타납니다. Return은 확정하고
  Escape는 편집 시작 때의 제목으로 되돌립니다. 둘 다 편집을 끝내고 포커스를 목록에 돌려줍니다. (STA-38에서 도입, 실제 앱 미검증.
  서체관리자·Finder의 이름 변경 동작을 기준으로 합니다.)
- 본문: 텍스트 Drop은 텍스트(선택·복사 가능), 이미지 Drop은 이미지 미리보기, 이미지를 못 읽으면 대체 표시.
- 선택 없음: 안내 문구 `selectHint`.
- 삭제는 확인 시트를 거쳐 폴더 전체를 휴지통으로 옮깁니다. 휴지통 이동 후에도 폴더가 남아 있으면 실패입니다.

### 2.7 인스펙터

- `정보` 제목, `노트`(여러 줄 입력, 저장 상태 표시: `automaticSave`/`changesPending`/`saving`/`saved`/`saveFailed`), `태그`(입력 + 등록 버튼 + 삭제 가능한
  칩 목록 + 힌트), `출처`(앱 아이콘, 앱 이름, `저장 {시각}`)와 `출처 상세 정보` 펼침(윈도우 제목, 수정 시각, URL, 파일 경로 중
  **있는 것만**, URL과 파일 경로는 복사 버튼).
- 자동 저장: 편집 후 600 ms 디바운스, 입력 필드를 떠날 때(blur) 즉시 저장. 저장이 실패한 상태에서는 blur로 재시도하지 않고
  `다시 시도` 버튼을 줍니다. 제목이 공백이면 저장하지 않고 `blankTitle` 오류를 표시합니다. 다른 Drop을 선택하면 편집 상태를
  초기화합니다. 저장 응답이 도착했을 때 이미 다른 Drop이거나 더 새 편집이 있으면 그 응답을 반영하지 않습니다.
- 태그 입력: Enter 또는 쉼표로 등록. **한글 등 입력기 조합 중에는(`isComposing` 또는 keyCode 229) 등록하지 않습니다.**
  이미 있는 태그를 추가하면 `tagAlreadyAdded` 안내. 등록 뒤 입력창에 포커스를 유지합니다. Escape는 입력창을 떠납니다.
- 등록 전 초안과 삭제 가능한 태그 칩을 시각적으로 구분합니다.

## 3. 캡처

### 3.1 선택 텍스트 캡처

트리거는 전역 단축키(기본 `Shift+Cmd+C`) 하나이며 확인 방식(3.3)을 적용하고 별도 Save Popup 창을 엽니다. 도구 막대의
`선택한 텍스트 캡처` 버튼은 두지 않습니다. 최전면 앱이 Notedrop 자신이라 다른 앱의 선택을 가져올 수 없기 때문입니다(체크리스트 D-05).

캡처는 두 경로를 이 순서로 시도합니다. 단계 번호의 순서는 바꾸면 안 됩니다.

1. **출처 수집을 먼저** 합니다(3.4). 이 시점의 최전면 앱이 원본이기 때문입니다.
2. **접근성 읽기(1순위, 클립보드를 건드리지 않음)**: 최전면 앱의 프로세스로 만든 접근성 요소(`AXUIElementCreateApplication`)에서
   포커스된 요소의 선택 텍스트(`AXSelectedText`)를 읽습니다. 시스템 전역 요소(`AXUIElementCreateSystemWide`)는 Chrome에서
   실패하므로 쓰지 않습니다. 짧은 타임아웃을 걸고, 최전면 앱이 Notedrop이면 건너뜁니다. 비어 있지 않은 값이 나오면 7단계로
   갑니다(클립보드 백업·복원 없음). 읽기에 실패하거나 값이 비면 폴백으로 넘어가며 이것만으로 `no_selected_text`로 보지 않습니다.
   앱별 결과는 [ax-probe.md](ax-probe.md)에 있습니다.
3. **클립보드 폴백**: 클립보드를 백업합니다(텍스트와 PNG 이미지). 실패하면 경고 `clipboard_backup_failed`를 남기고 빈 스냅샷으로 계속합니다.
4. `Cmd+C`를 시뮬레이션합니다.
5. 클립보드 변경 횟수(change count)가 백업 시점과 달라질 때까지 25 ms 간격으로 최대 700 ms 기다립니다. 변경 횟수가
   달라졌을 때 문자열을 읽습니다. 변경 횟수를 얻지 못한 경우에만 텍스트 값 비교로 대체합니다.
6. **결과와 무관하게** 이전 클립보드를 복원합니다(3~5단계를 거친 경우만). 복원에 실패하면 경고 `clipboard_restore_failed`를
   추가하고 캡처는 성공으로 처리합니다. 백업이 불완전했다면 복원을 시도하되 마지막에 실패로 보고합니다.
7. 텍스트의 끝 `\r`/`\n`을 제거하고 공백뿐이면 비어 있는 것으로 봅니다. 비면 `no_selected_text`.
   복사된 텍스트가 이전 클립보드와 같더라도(변경 횟수만 달라졌다면) 유효합니다.
8. 제목을 추론하고(1.4) Draft(`type: text`, 노트 없음, 태그 없음, 경고 목록)를 만듭니다.

복사 시뮬레이션이나 대기 중 자동화 오류(`automation_unavailable`, `automation_failed`)는 `permission_missing`으로 바꾸고
`손쉬운 사용 권한을 System Settings에서 허용하라`는 안내를 덧붙입니다.

### 3.2 클립보드 캡처

트리거: 메뉴 막대의 `Save Clipboard...`. (PRD에 있는 `Shift+Cmd+V`는 구현된 적이 없습니다. 체크리스트 D-01.)

1. 변경 횟수를 읽고 클립보드의 문자열과 이미지(PNG 우선, 없으면 TIFF를 PNG로 변환)를 한 번에 읽습니다.
2. 읽는 동안 변경 횟수가 바뀌었으면 `clipboard_changed`로 실패합니다.
3. 이미지가 있는데 디코딩에 실패하면 경고 `clipboard_image_unavailable`을 남기고 텍스트만으로 진행합니다. 텍스트도 없으면
   그 오류로 실패합니다.
4. 분류: 텍스트만 → `text`, 이미지만 → `image`, 둘 다 → `mixed`, 둘 다 없으면 `clipboard_empty`.
5. 출처를 수집합니다. 최전면 앱이 Notedrop 자신이면(메뉴 막대에서 실행) 출처를 비우고 제목을 다시 추론합니다.

### 3.3 확인 방식

전역 단축키와 메뉴 막대 `Save Clipboard...`에 적용하는 설정 `captureConfirmationMode`:

- `modal`: 항상 Save Popup을 엽니다.
- `instant`: **텍스트 Draft만** 노트와 태그 없이 즉시 저장하고 메뉴 막대에 `Saved`를 보여 준 뒤 Library 새로고침 신호를 보냅니다.
  이미지와 `mixed` Draft는 `instant`에서도 팝업을 엽니다.

저장 실패는 다음처럼 처리합니다. 선택 텍스트 캡처 실패는 오류를 보관하고 메인 창을 열고 메뉴 막대에 `Error`를 표시합니다.
클립보드 캡처 실패는 오류를 보관하고 `Error`만 표시합니다. 보관한 오류는 메인 창이 열렸을 때 **한 번만** 꺼내어
`{pendingFailed}: {메시지}` 상태 메시지로 보여 줍니다.

### 3.4 출처 수집 (최선 노력)

실패해도 저장을 막지 않고 경고만 남깁니다.

- 최전면 앱 이름과 앞 윈도우 제목(제목을 못 얻으면 빈 값).
- 최전면 앱이 `Google Chrome`이면 앞 창의 활성 탭 URL. 실패 시 경고 `chrome_url_failed`. 앱·윈도우 수집 실패는
  `metadata_failed`.
- 파일 경로는 신뢰할 수 있는 API가 있을 때만. 레거시는 수집하지 않습니다.

### 3.5 Save Popup

- 내용: 유형 표시(저장 대상), 텍스트 또는 이미지 미리보기, 출처 요약(`앱 · 윈도우 · URL`, 없으면 `알 수 없는 출처`),
  경고, 노트 입력(선택), 태그 입력, 최근 태그 칩(누르면 입력에 추가, 이미 있으면 무시), 저장 버튼, 취소 버튼, 닫기.
- `mixed` Draft: 텍스트/이미지 중 **하나를 고르게** 합니다. 고른 유형 하나만 Drop으로 저장합니다.
- `Cmd+Enter`는 저장(저장 중이면 무시), Escape와 닫기 버튼은 취소. 열릴 때 팝업에 포커스합니다.
- 별도 창 팝업: Draft를 받기 전에는 `preparing` 문구를 보여 줍니다. 저장 성공 시 최근 태그를 갱신하고 Library 새로고침 신호를
  보낸 뒤 창을 닫습니다. Library는 새로고침 후 저장된 새 Drop을 선택합니다(체크리스트 L-10). 취소해도 창을 닫고 Draft를
  버립니다.
- 저장 실패: 팝업을 닫지 않고 오류를 표시합니다.
- 별도 창 팝업이 이미 열려 있을 때 단축키로 다시 캡처하면 같은 창을 재사용하고 새 Draft가 이전 Draft를 대체합니다
  (체크리스트 P-14).
- 별도 창 팝업의 크기와 위치는 2.1을 따르며, 팝업에도 앱의 테마 설정을 적용합니다.

## 4. 설정 화면

메인 창 안의 화면이며 사이드바는 Library와 같습니다. 내용: 저장 폴더(경로 표시, 폴더 선택 버튼, 선택을 취소하면 `folderCancelled`
안내), 테마(시스템/라이트/다크, 앱 외형에 즉시 적용하고 시스템으로 돌아가면 재정의 해제), 선택 텍스트 단축키(입력, 저장, 형식
안내, 저장 중 상태), 저장 확인 방식(팝업 표시/텍스트 즉시 저장), 권한 상태, 앱 버전.

- 저장 폴더를 바꾸면 이후의 스캔과 저장이 새 폴더를 씁니다. 기존 Drop을 옮기거나 복사하지 않습니다.
- 첫 실행(`hasCompletedFirstRun == false`): 모달로 기본 폴더 사용 또는 폴더 선택을 요구하고, 둘 중 하나가 끝나면
  `hasCompletedFirstRun = true`로 저장합니다. 선택을 취소하면 모달이 남습니다.
- 단축키를 바꾸면 새 단축키를 먼저 등록하고 이전 것을 해제한 뒤 설정을 저장합니다. 등록 실패나 저장 실패면 이전 단축키를
  유지(롤백)하고 설정 파일은 바뀌지 않습니다. 형식이 잘못되면 저장하지 않고 `invalid_selected_text_shortcut`을 보여 줍니다.
- 권한 상태 세 항목: 손쉬운 사용(`AXIsProcessTrusted`), 클립보드(텍스트를 읽을 수 있는지), 자동화(항상 `알 수 없음`, Chrome
  URL을 처음 읽을 때 시스템이 묻는다는 안내). 각 항목은 상태(허용/없음/알 수 없음), 설명, 다음 행동을 가집니다.

## 5. 외형과 지역화

- 테마와 색: `design-system.md`의 의미 토큰, 다크 시안 기준, 라이트·다크 모두 지원.
- 폰트: 시스템 폰트.
- 지역화: 시스템 언어가 `ko`로 시작하면 한국어, 아니면 영어. 날짜·시각은 로케일(`ko-KR`/`en-US`) 형식.
- 아이콘: SF Symbols를 직접 사용합니다. 레거시가 정한 의미 이름과 기호 대응은 아래와 같습니다(16 pt, regular 기준).

| 의미 이름 | SF Symbol |
| --- | --- |
| library | `tray.full` |
| text | `textformat` |
| image | `photo` |
| tag | `tag` |
| settings | `gearshape` |
| sourceApp | `macwindow` |
| fileText | `doc.text` |
| folder | `folder` |
| filter | `line.3.horizontal.decrease` |
| clearFilters | `arrow.counterclockwise` |
| calendar | `calendar` |
| copy | `doc.on.doc` |
| check | `checkmark` |
| export | `square.and.arrow.down` |
| openSource | `arrow.up.right.square` |
| trash | `trash` |
| add | `plus` |
| close | `xmark` |
| selectText | `text.cursor` |
| save | `tray.and.arrow.down` |
| refresh | `arrow.clockwise` |
| loading | `progress.indicator` |
| keyboard | `keyboard` |
| system | `desktopcomputer` |
| light | `sun.max` |
| dark | `moon` |
| permissions | `checkmark.shield` |
| shortcut | `bolt` |
| success | `checkmark.circle` |
| error | `exclamationmark.circle` |
| info | `info.circle` |
| warning | `exclamationmark.triangle` |

- 접근성: 모든 아이콘 버튼에 레이블, 선택 상태를 색만으로 전달하지 않음, 키보드만으로 전체 흐름 수행, 고대비·투명도 감소·모션
  감소 설정 존중. 상세 기준은 design-system.md.

## 6. 오류와 경고

사용자에게 보이는 메시지는 `i18n.tsx`의 사전(`translateError`가 쓰는 키)에 있습니다. 코드는 아래를 유지합니다.

| 코드 | 의미 | 저장 차단 |
| --- | --- | --- |
| `no_selected_text` | 선택한 텍스트 없음 | — |
| `clipboard_empty` | 지원하는 클립보드 내용 없음 | — |
| `clipboard_unavailable` | 클립보드를 읽지 못함 | — |
| `clipboard_changed` | 읽는 중 클립보드가 바뀜 | — |
| `clipboard_image_unavailable` | 이미지 디코딩 실패, 또는 비었거나 PNG가 아닌 이미지 | — |
| `clipboard_restore_failed` | 이전 클립보드 복원 실패(경고) | 아니오 |
| `permission_missing` / `automation_*` | 손쉬운 사용·자동화 권한 필요 | — |
| `empty_text`, `empty_image`, `invalid_image` | 저장할 내용이 없거나 PNG가 아님 | 예 |
| `invalid_title` | 제목이 공백 | 예 |
| `invalid_storage_folder`, `storage_unwritable`, `storage_unreadable` | 저장 폴더 문제 | 예 |
| `drop_not_found`, `invalid_drop_id`, `delete_failed` | Drop 조회·삭제 문제 | 예 |
| `source_url_missing`, `source_url_open_failed` | 출처 URL 없음·열기 실패 | — |
| `settings_invalid`, `settings_unreadable`, `settings_unwritable`, `invalid_theme`, `invalid_capture_confirmation_mode` | 설정 문제 | 예 |
| `invalid_selected_text_shortcut`, `shortcut_registration_failed`, `shortcut_rollback_failed` | 단축키 문제 | 예 |

출처 수집 실패는 저장을 막지 않습니다. 저장소 실패는 저장을 막고 이유를 보여 줍니다. 오류는 복구 가능하게 처리하고 앱을
종료하지 않습니다.

## 7. Markdown 내보내기

`Markdown 내보내기`는 저장 대화상자(기본 파일명 `{slug(제목)}.md`, 필터 `md`)를 열고, 취소하면 아무것도 쓰지 않습니다.
내용은 다음 순서이며 값이 없는 줄과 섹션은 생략합니다.

```markdown
# {title}

## Metadata

- Type: {type}
- Created: {createdAt}
- Updated: {updatedAt}
- Tags: {tag, tag}
- App: {appName}
- Window: {windowTitle}
- URL: {url}
- File: {filePath}

## Text

{text}

## Note

{note}
```

Metadata의 `Type`, `Created`, `Updated`는 항상 있고, 나머지 항목과 `Text`·`Note` 섹션은 값이 있을 때만 출력합니다. 본문과
노트는 앞뒤 공백을 지우고 끝에 줄바꿈 하나를 붙입니다. 이미지 Drop에는 `Text`가 없습니다.

## 8. Swift 구현 제안 (구속력 없음)

| 영역 | 후보 |
| --- | --- |
| 3열 + 인스펙터 | `NavigationSplitView`와 `.inspector`. 좁은 폭의 오버레이 동작은 직접 확인. |
| 도구 막대와 검색 | SwiftUI `.toolbar`, `.searchable`. 아이콘 축약과 Escape 규칙은 직접 확인. |
| 클립보드 | `NSPasteboard`와 `changeCount`를 앱 안에서 직접 사용. 별도 `swift -e` 프로세스가 필요 없습니다. |
| 복사 시뮬레이션 | `CGEvent`(손쉬운 사용 권한 필요). |
| 출처 | `NSWorkspace.frontmostApplication`, 접근성 API로 윈도우 제목, Chrome URL은 `NSAppleScript`(`NSAppleEventsUsageDescription` 필요). |
| 전역 단축키 | Carbon `RegisterEventHotKey` 또는 검증된 라이브러리. 저장된 `Shift+Cmd+C` 문자열을 해석. |
| 휴지통 | `FileManager.trashItem`. |
| 메뉴 막대 | `NSStatusItem`. |
| 저장소 | `Codable`과 `FileManager`. 모델과 저장은 UI와 분리해 순수 단위 테스트가 가능하게. |

### 권장 구현 순서

1. 저장 계층(모델, 읽기·쓰기, 태그, ID, 설정)과 [픽스처](fixtures/README.md) 기반 호환 테스트.
2. Library 읽기 전용 화면(사이드바, 목록, 본문, 인스펙터, 도구 막대)과 서체관리자 대조.
3. 편집(제목, 노트, 태그, 자동 저장), 삭제, 내보내기.
4. 캡처(선택 텍스트, 클립보드), Save Popup, 출처 수집, 권한.
5. 설정, 단축키 변경, 메뉴 막대, 첫 실행.
6. [체크리스트](behavior-checklist.md) 전 항목 확인.
