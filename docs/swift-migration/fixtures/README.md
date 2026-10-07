# 호환성 픽스처

Linear: [STA-39](https://linear.app/byeoung/issue/STA-39)

모두 **합성 데이터**입니다(실제 사용자 Drop이 아님). 레거시 스캐너(`legacy/tauri`)에 실제로 돌려 아래 기대값을 확인했습니다.
Swift 구현은 같은 입력에서 같은 결과를 내야 합니다.

## 사용법

1. `fixtures/storage`를 임시 위치에 복사합니다.
2. `settings.json`의 `storageFolderPath`를 그 복사본의 절대 경로로 바꿉니다.
3. 읽기·쓰기 테스트는 복사본에서만 수행합니다. 픽스처 원본은 수정하지 않습니다.

## `storage/drops` 기대 결과

정렬은 `createdAt` 내림차순, 같으면 `id` 내림차순입니다. 경고는 1개입니다.

| 순서 | 폴더 | 기대 |
| --- | --- | --- |
| 1 | `2026-01-06_…_mixed` | `type: mixed`. 목록에는 나타나고 깨지지 않아야 합니다. 레거시는 `mixed`의 본문·이미지를 읽지 않아 `text`와 이미지가 비어 있습니다(체크리스트 D-02). |
| 2 | `2026-01-04_…_legacy-minimal-text` | 선택 키가 모두 없는 `drop.json`. 태그 `["#Research","research"," Swift ","","##Two Words"]`는 `["research","swift","two words"]`로 정규화(앞쪽 `#` 제거, 소문자, 중복·빈 값 제거, 내부 공백 유지). `note.md`가 없으면 노트 없음. `source`는 빈 값. |
| 3 | `2026-01-04_…_legacy-minimal-image` | `imagePath` 키가 없어도 `image.png`를 이미지로 읽습니다. 노트 없음. |
| 4 | `2026-01-03_…_image-drop` | 일반 이미지 Drop. 노트 `Whiteboard photo.`. |
| 5 | `2026-01-02_…_drop` | 한글 제목과 태그. ID의 slug는 `drop`(한글은 slug에서 제거). 빈 `note.md`는 노트 없음. URL이 있는 출처. |
| 6 | `2026-01-01_…_example-app` | 일반 텍스트 Drop. 본문 두 문단, 노트에 마크다운 보존(끝 줄바꿈 포함). |
| — | `2026-01-05_…_broken-json` | `drop.json`이 깨짐. 목록에서 제외되고 경고 `drop_scan_skipped` 1개. |
| — | `not-a-drop.txt` | `drops/` 바로 아래의 파일. 무시합니다. |

2번과 3번은 `createdAt`이 같아서 `id` 내림차순(`…-text` > `…-image`)이 순서를 정합니다.

모든 `drop.json`은 저장된 형식(`text`, `note`가 `null`, `imagePath`는 텍스트에서 `null`)을 따르지만 2번·3번만 의도적으로
최소 키입니다. 이 앱이 파일을 다시 쓰면 키 집합이 체크리스트 S-01을 따라 정규화되어야 합니다.

## 설정 파일 기대 결과

| 파일 | 기대 읽기 결과 |
| --- | --- |
| `settings.json` | 그대로. `theme: dark`, `paneWidths {215, 373}`, `recentTags ["research","swift"]`. |
| `settings-legacy.json` | 선택 키가 없어도 읽힙니다. `theme: sepia`는 `system`으로 보정, `captureConfirmationMode: modal`, `selectedTextShortcut: Shift+Cmd+C`, `paneWidths {220, 330}`, `recentTags []`. `hasCompletedFirstRun: false`. |
| `settings-clamp.json` | `storageFolderPath`가 공백이면 기본 저장 폴더, `selectedTextShortcut`가 공백이면 `Shift+Cmd+C`, `paneWidths {180, 560}`으로 고정, `recentTags`는 정규화 후 앞의 12개(`a`…`l`), `captureConfirmationMode: instant`는 유효. |

필수 키는 `storageFolderPath`, `hasCompletedFirstRun`, `theme`, `updatedAt`입니다. 하나라도 없으면 `settings_invalid`입니다
(픽스처로 두지 않았으므로 단위 테스트에서 직접 만드세요).

## 직접 만들어야 하는 입력

다음은 파일로 두기 부적합하거나 민감하므로 테스트 코드에서 만드세요: 읽기 권한이 없는 폴더, 쓰기 불가 저장 폴더, 같은 ID가
이미 있는 폴더, `drops/`가 없는 저장 폴더, 깨진 `settings.json`, 소수 자리 수가 다른 시각.
