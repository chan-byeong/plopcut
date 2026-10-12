# 문구 사전 (en / ko)

Linear: [STA-39](https://linear.app/byeoung/issue/STA-39)

레거시 `src/i18n/i18n.tsx`에서 그대로 추출한 사용자 문구입니다. 키는 [스펙](spec.md)과 [체크리스트](behavior-checklist.md)가 참조하는 이름입니다. 시스템 언어가 `ko`로 시작하면 한국어, 아니면 영어를 씁니다. 두 언어의 키 집합은 같습니다(158개). `shortcutFormatHint`만 구현 용어(Tauri)를 말하므로 Swift 구현의 단축키 형식에 맞게 고쳐 씁니다(체크리스트 D-12). `{count}` 같은 자리 표시자는 치환합니다.

Swift 구현에서만 추가한 키는 레거시 사전에 없다: `appLogo`(STA-72, 로고 접근성 라벨), `dropCountOne`(영어 단수형), `dropTitle`(제목 입력란 접근성 라벨), `ok`(알림 단추), `unreadableDrops`(읽지 못한 드롭 경고, STA-80).

| 키 | en | ko |
| --- | --- | --- |
| `collections` | Collections | 보관함 |
| `information` | Information | 정보 |
| `tagEntryHint` | Enter to add · Separate with commas. | Enter로 추가 · 쉼표로 구분. |
| `library` | Library | 라이브러리 |
| `librarySidebar` | Library sidebar | 라이브러리 사이드바 |
| `inspector` | Information inspector | 정보 인스펙터 |
| `text` | Text | 텍스트 |
| `images` | Images | 이미지 |
| `tags` | Tags | 태그 |
| `noTags` | No tags | 태그 없음 |
| `settings` | Settings | 설정 |
| `refreshLibrary` | Refresh library | 라이브러리 새로고침 |
| `capture` | Capture | 캡처 |
| `openSettings` | Open settings | 설정 열기 |
| `saveClipboard` | Save Clipboard... | 클립보드 저장... |
| `openLibrary` | Open library | 라이브러리 열기 |
| `showSidebar` | Show sidebar | 사이드바 표시 |
| `hideSidebar` | Hide sidebar | 사이드바 숨기기 |
| `showInspector` | Show inspector | 인스펙터 표시 |
| `hideInspector` | Hide inspector | 인스펙터 숨기기 |
| `resizeSidebarAndLibrary` | Resize sidebar and library panes | 사이드바와 라이브러리 영역 크기 조절 |
| `resizeLibraryAndDetail` | Resize library and detail panes | 라이브러리와 상세 영역 크기 조절 |
| `sidebarPanelHelp` | Shows or hides the Library sidebar panel. | 라이브러리 사이드바 패널을 표시하거나 숨깁니다. |
| `inspectorPanelHelp` | Shows or hides the Information inspector panel. | 정보 인스펙터 패널을 표시하거나 숨깁니다. |
| `imagePreviewUnavailable` | Image preview unavailable | 이미지 미리보기를 사용할 수 없습니다 |
| `search` | Search drops | 드롭 검색 |
| `searchPlaceholder` | Search title, text, note, tag, source… | 제목, 텍스트, 노트, 태그, 출처 검색… |
| `clearSearch` | Clear search | 검색 지우기 |
| `drops` | drops | 개 |
| `allDrops` | All drops | 모든 드롭 |
| `textDrops` | Text drops | 텍스트 드롭 |
| `imageDrops` | Image drops | 이미지 드롭 |
| `openFilters` | Open filters | 필터 열기 |
| `clearFilters` | Clear filters | 필터 지우기 |
| `activeFilters` | Active filters | 적용된 필터 |
| `removeFilter` | Remove filter | 필터 제거 |
| `dropCount` | {count} drops | {count}개의 드롭 |
| `dropCountOne` | 1 drop | 1개의 드롭 |
| `filterTag` | Filter by tag | 태그로 필터 |
| `filterApp` | Filter by app | 앱으로 필터 |
| `filterDate` | Filter by date | 날짜로 필터 |
| `allTags` | All tags | 모든 태그 |
| `allApps` | All apps | 모든 앱 |
| `anyTime` | Any time | 전체 기간 |
| `last7` | Last 7 days | 최근 7일 |
| `last30` | Last 30 days | 최근 30일 |
| `today` | Today | 오늘 |
| `yesterday` | Yesterday | 어제 |
| `previous7` | Previous 7 Days | 지난 7일 |
| `older` | Older | 이전 |
| `loadingDrops` | Loading drops… | 드롭 불러오는 중… |
| `noMatches` | No drops match the current filters | 현재 필터와 일치하는 드롭이 없습니다 |
| `noDrops` | No saved drops yet. Capture text with Shift + Cmd + C. | 저장된 드롭이 없습니다. Shift + Cmd + C로 텍스트를 캡처하세요. |
| `appLogo` | Notedrop logo | Notedrop 로고 |
| `dropTitle` | Drop title | 드롭 제목 |
| `ok` | OK | 확인 |
| `unreadableDrops` | Some drops could not be read ({count}) | 일부 드롭을 읽지 못했습니다 ({count}) |
| `selectedDrop` | Selected drop | 선택한 드롭 |
| `drop` | drop | 드롭 |
| `unsaved` | Unsaved changes | 저장되지 않은 변경 |
| `automaticSave` | Automatic save | 자동 저장 |
| `changesPending` | Changes pending | 변경됨 |
| `saving` | Saving… | 저장 중… |
| `saved` | Saved | 저장됨 |
| `saveFailed` | Save failed | 저장 실패 |
| `retrySave` | Retry | 다시 시도 |
| `blankTitle` | Drop title cannot be blank. | 드롭 제목을 비워둘 수 없습니다. |
| `openSource` | Open Source | 출처 열기 |
| `copyContent` | Copy Content | 내용 복사 |
| `exportMarkdown` | Export Markdown | Markdown 내보내기 |
| `moveTrash` | Move to Trash | 휴지통으로 이동 |
| `copyUrl` | Copy URL | URL 복사 |
| `copyFile` | Copy file path | 파일 경로 복사 |
| `note` | Note | 노트 |
| `noNote` | No note… | 노트 없음… |
| `tagPlaceholder` | research, quote… | 리서치, 인용… |
| `tagAlreadyAdded` | Already added | 이미 추가됨 |
| `removeTag` | Remove | 제거 |
| `source` | Source | 출처 |
| `sourceDetails` | Source details | 출처 상세 정보 |
| `app` | App | 앱 |
| `window` | Window | 윈도우 |
| `url` | URL | URL |
| `file` | File | 파일 |
| `savedAt` | Saved | 저장 |
| `updatedAt` | Updated | 수정 |
| `unknown` | Unknown | 알 수 없음 |
| `selectHint` | Select text in another app, then press Shift + Cmd + C. | 다른 앱에서 텍스트를 선택한 뒤 Shift + Cmd + C를 누르세요. |
| `confirmTrash` | Move to Trash? | 휴지통으로 이동할까요? |
| `confirmTrashBody` | This drop will be moved to the system Trash. | 이 드롭은 시스템 휴지통으로 이동됩니다. |
| `cancel` | Cancel | 취소 |
| `move` | Move | 이동 |
| `general` | General | 일반 |
| `captureSection` | Capture | 캡처 |
| `permissions` | Permissions | 권한 |
| `about` | About | 정보 |
| `storageFolder` | Storage folder | 저장 폴더 |
| `chooseFolder` | Choose storage folder | 저장 폴더 선택 |
| `theme` | Theme | 테마 |
| `system` | System | 시스템 |
| `light` | Light | 라이트 |
| `dark` | Dark | 다크 |
| `captureShortcut` | Shortcut format | 단축키 형식 |
| `selectedTextShortcut` | Selected text shortcut | 선택 텍스트 단축키 |
| `shortcutExample` | Example: Shift+Cmd+K | 예시: Shift+Cmd+K |
| `shortcutFormatHint` | Join modifiers and a key with +, for example Shift+Cmd+K. F21–F24 are not supported. | 수식키와 키를 +로 연결하세요. 예: Shift+Cmd+K (F21–F24는 지원하지 않습니다) |
| `shortcutRegistrationFailed` | Could not register that shortcut. Another app may already use it. The previous shortcut still works. | 이 단축키를 등록하지 못했습니다. 다른 앱이 이미 사용 중일 수 있습니다. 이전 단축키는 그대로 동작합니다. |
| `shortcutRollbackFailed` | The shortcut could not be saved and the previous one could not be restored. Set a shortcut again. | 단축키를 저장하지 못했고 이전 단축키도 복원하지 못했습니다. 단축키를 다시 설정하세요. |
| `shortcutField` | Shortcut | 단축키 |
| `shortcutRecording` | Press keys… | 키를 누르세요… |
| `shortcutRecordHint` | Click the field and press the new key combination. Esc cancels the recording. | 입력란을 클릭하고 새 키 조합을 누르세요. Esc를 누르면 입력을 취소합니다. |
| `shortcutUnsaved` | Not saved yet. The current shortcut keeps working until you press Save. | 아직 저장하지 않았습니다. 저장을 누르기 전까지 기존 단축키가 그대로 동작합니다. |
| `shortcutNeedsModifier` | Hold Shift, Cmd, Ctrl or Option together with the key. | Shift, Cmd, Ctrl, Option 중 하나 이상을 함께 누르세요. |
| `shortcutUnsupportedKey` | That key can't be used. Use a letter, a number, F1–F20, an arrow, Space, Enter, Tab, Esc, Backspace, Delete, Home, End, Page Up or Page Down. | 이 키는 쓸 수 없습니다. 문자, 숫자, F1–F20, 방향키, Space, Enter, Tab, Esc, Backspace, Delete, Home, End, Page Up, Page Down 중에서 고르세요. |
| `captureConfirmation` | Save confirmation | 저장 확인 |
| `modal` | Show popup | 팝업 표시 |
| `instant` | Save text instantly | 텍스트 즉시 저장 |
| `appVersion` | App version | 앱 버전 |
| `permissionStatus` | Permission status | 권한 상태 |
| `loadingPermissions` | Loading permissions… | 권한 확인 중… |
| `accessibility` | Accessibility | 손쉬운 사용 |
| `clipboard` | Clipboard | 클립보드 |
| `automation` | Automation | 자동화 |
| `granted` | Granted | 허용됨 |
| `missing` | Needs permission | 권한 필요 |
| `permissionUnknown` | Unknown | 알 수 없음 |
| `permissionAccessibilityGranted` | Keyboard simulation and active window access are available. | 키보드 시뮬레이션과 활성 윈도우 접근을 사용할 수 있습니다. |
| `permissionAccessibilityMissing` | Allow Notedrop in System Settings › Privacy & Security › Accessibility. | 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 Notedrop을 허용하세요. |
| `permissionClipboardGranted` | Clipboard content is read only when you use a capture action. | 캡처 동작을 실행할 때만 클립보드 내용을 읽습니다. |
| `permissionClipboardMissing` | Clipboard access is required for explicit captures. | 명시적인 캡처에 클립보드 접근이 필요합니다. |
| `permissionAutomationGranted` | Chrome source URLs can be collected during capture. | 캡처 중 Chrome 출처 URL을 가져올 수 있습니다. |
| `permissionAutomationMissing` | Allow browser automation when macOS asks for access. | macOS가 요청할 때 브라우저 자동화를 허용하세요. |
| `permissionUnknownDetail` | Notedrop could not determine this permission status. | 이 권한 상태를 확인하지 못했습니다. |
| `permissionAutomationNote` | macOS asks for access the first time Notedrop reads the Chrome URL. | Notedrop이 Chrome URL을 처음 읽을 때 macOS가 접근을 묻습니다. |
| `openSystemSettings` | Open System Settings | 시스템 설정 열기 |
| `saveText` | Save Text Drop | 텍스트 드롭 저장 |
| `saveImage` | Save Image Drop | 이미지 드롭 저장 |
| `unknownApp` | Unknown app | 알 수 없는 앱 |
| `unknownWindow` | Unknown window | 알 수 없는 윈도우 |
| `optionalNote` | Optional note… | 선택 사항… |
| `recentTags` | Recent tags | 최근 태그 |
| `addTag` | Add tag | 태그 추가 |
| `save` | Save | 저장 |
| `preparing` | Preparing capture | 캡처 준비 중 |
| `chooseType` | Drop type to save | 저장할 드롭 유형 |
| `image` | Image | 이미지 |
| `capturing` | Capturing selected text… | 선택한 텍스트 캡처 중… |
| `captureSaved` | Drop saved. | 드롭을 저장했습니다. |
| `pendingFailed` | Save failed | 저장 실패 |
| `folderCancelled` | Folder selection cancelled. | 폴더 선택을 취소했습니다. |
| `folderSet` | Storage folder updated. | 저장 폴더를 변경했습니다. |
| `folderConfirmed` | Storage folder confirmed. | 저장 폴더를 확인했습니다. |
| `trashSuccess` | Drop moved to Trash. | 드롭을 휴지통으로 이동했습니다. |
| `exportCancelled` | Markdown export cancelled. | Markdown 내보내기를 취소했습니다. |
| `exportSuccess` | Markdown exported. | Markdown을 내보냈습니다. |
| `updated` | Drop updated. | 드롭을 수정했습니다. |
| `defaultError` | Notedrop could not complete the action. | Notedrop이 작업을 완료하지 못했습니다. |
| `panelFocusRestoreFailed` | The panel closed, but keyboard focus could not return to its toolbar button. | 패널을 닫았지만 도구 막대 버튼으로 키보드 포커스를 돌리지 못했습니다. |
| `chooseStorage` | Choose Storage Folder | 저장 폴더 선택 |
| `firstRunBody` | Notedrop saves readable drop files locally. Confirm the default folder or choose another folder before using the Library. | Notedrop은 읽을 수 있는 드롭 파일을 로컬에 저장합니다. 라이브러리를 사용하기 전에 기본 폴더를 확인하거나 다른 폴더를 선택하세요. |
| `chooseFolderAction` | Choose Folder | 폴더 선택 |
| `useDefaultFolder` | Use Default Folder | 기본 폴더 사용 |
| `dismiss` | Dismiss status | 상태 메시지 닫기 |
| `noCaptured` | No captured content is available. | 캡처한 내용이 없습니다. |
| `noSelectedText` | No selected text was found. Select text and press Shift + Cmd + C. | 선택한 텍스트가 없습니다. 텍스트를 선택하고 Shift + Cmd + C를 누르세요. |
| `clipboardEmpty` | The clipboard has no supported text or image. | 클립보드에 지원되는 텍스트나 이미지가 없습니다. |
| `clipboardUnavailable` | Notedrop could not read the clipboard. | 클립보드를 읽지 못했습니다. |
| `clipboardChanged` | The clipboard changed while it was being read. Try Save Clipboard again. | 읽는 중 클립보드 내용이 바뀌었습니다. 클립보드 저장을 다시 실행하세요. |
| `clipboardRestoreFailed` | The capture succeeded, but the previous clipboard could not be restored. | 캡처는 완료했지만 이전 클립보드를 복원하지 못했습니다. |
| `automationFailed` | Source metadata could not be collected. You can still save the drop. | 출처 메타데이터를 가져오지 못했습니다. 드롭은 계속 저장할 수 있습니다. |
| `invalidImage` | The clipboard image could not be read. | 클립보드 이미지를 읽지 못했습니다. |
| `storageFailure` | The storage folder is missing or not writable. | 저장 폴더가 없거나 쓸 수 없습니다. |

## 문구 점검 기록 (STA-80)

- `shortcutRecordHint`(ko): "녹화를 취소합니다"는 영상 녹화로 읽혀 "입력을 취소합니다"로 고쳤다.
- `removeTag`(ko): `removeFilter`("제거")와 같은 동사로 맞추려 "삭제"를 "제거"로 고쳤다.
- 영어 단수형: `dropCountOne` 추가(`1 drops` 방지). 한국어는 단수·복수 구분이 없다.
- 하드코딩 영어 제거: 읽지 못한 드롭 경고(`unreadableDrops`), 알림창 단추(`ok`). 접근성 라벨 `dropTitle` 추가.
- 의도적으로 그대로 둠: `Save Clipboard...`(세 점, 스펙·체크리스트가 같은 표기를 쓴다), 미리보기가 없을 때의 영어 `No preview`(스펙 2.5), 그룹 제목의 `Previous 7 Days`(macOS 목록 머리글 표기).
- `StringTable.swift`와 이 표가 같은 키·문구를 가지는지는 `AccessibilityAndCopyTests.stringTableMatchesStringsMarkdown`이 검사한다(`shortcutFormatHint`는 Swift 단축키 형식으로 고쳐 쓰므로 제외).
