# 동작 체크리스트

Linear: [STA-39](https://linear.app/byeoung/issue/STA-39) · 사양: [spec.md](spec.md) · 픽스처: [fixtures/](fixtures/README.md)

레거시 코드와 PRD에만 남아 있고 화면만 봐서는 놓치기 쉬운 동작을 모았습니다. 구현이 끝나면 항목마다 "확인 방법"을 수행해
체크하세요. **근거**는 레거시(`legacy/tauri` 브랜치) 파일입니다. 그 파일을 읽어야 한다는 뜻이 아니라, 동작에 의문이 생겼을 때
찾아볼 위치입니다. 함수 이름이 `테스트:`로 시작하면 레거시 테스트가 그 동작을 고정하고 있으므로 같은 시나리오를 Swift 테스트로
옮기면 됩니다.

체크 표시 ☑는 구현과 자동 테스트로 확인한 항목입니다(STA-41, `NotedropCore`). 일부만 확인한 항목은 ☐로 두고 아래에 이유를 적습니다.

확인 방법 표기: **단위** = 자동 테스트, **픽스처** = `fixtures/`로 호환 확인, **수동** = 실제 앱·macOS 권한이 필요한 확인.

## S. 저장소 (호환성 계약)

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| S-01 | `drop.json`을 2칸 들여쓰기 pretty JSON으로 쓰고, `text`, `note`, `imagePath`(텍스트)를 `null`로 쓴다. `imageDataUrl`은 쓰지 않는다. | `storage.rs` `write_drop_metadata` | 픽스처: 저장 후 파일이 `text-basic`과 같은 키 집합 | ☑ |
| S-02 | 읽을 때 `source`, `tags`, `text`, `note`, `imagePath` 누락을 허용한다. `id`, `type`, `title`, `createdAt`, `updatedAt` 누락만 오류. | `models.rs` `#[serde(default)]` | 픽스처: `legacy-minimal-text` | ☑ |
| S-03 | JSON이 깨진 Drop 폴더는 건너뛰고 경고(`drop_scan_skipped`)만 남기며 나머지 목록은 정상. | 테스트: `scan_sorts_newest_first_and_skips_corrupted_drop_folders` | 픽스처: `broken-json` 포함 스캔 | ☑ |
| S-04 | 목록은 `createdAt` 내림차순(문자열 비교), 같으면 `id` 내림차순. | `scan_drops_from_root` | 단위 | ☑ |
| S-05 | 시각은 UTC, 소수 9자리, `Z`. 소수 자리 수가 다르면 문자열 정렬이 틀어지므로 항상 9자리로 쓴다. Swift의 기본 ISO8601 포맷터는 밀리초만 쓴다. | `storage.rs` `current_timestamp` | 단위: 두 시각의 문자열 정렬 = 시간 정렬 | ☑ |
| S-06 | ID는 `{날짜}_{HHMMSS}_{나노초9}_{slug}`, 충돌 시 `-2`, `-3`. | `unique_drop_id` | 단위: 같은 ID로 연속 저장 | ☑ |
| S-07 | slug는 ASCII 영숫자만 남기고 48자에서 멈추며 한글만 있으면 `drop`. | `slugify` | 단위: `"한글 제목"`→`drop`, 긴 제목, 특수문자 연속 | ☑ |
| S-08 | 제목 추론: 명시 → 윈도우 제목 → 앱 이름 → 본문 첫 줄 → `Untitled Drop`, 최대 80자. 이미지는 `Image Drop`. | `infer_title` | 단위 | ☑ |
| S-09 | 본문은 끝의 `\r`/`\n`만 제거해 `content.md`에 저장. 공백뿐인 텍스트는 `empty_text`로 거부. | `save_text_drop_to_root` | 단위 | ☑ |
| S-10 | 이미지 바이트가 비면 `empty_image`로 거부. | `save_image_drop_to_root` | 단위 | ☑ |
| S-11 | 새 Drop은 `note.md`를 항상 만든다(비어 있어도). 노트 편집은 `note.md`를 항상 덮어쓴다. | `write_text_drop_files`, `update_text_drop_in_root` | 단위 | ☑ |
| S-12 | 읽을 때 공백뿐인 `note.md`는 "노트 없음"으로 취급. | `read_drop_folder` | 단위 | ☑ |
| S-13 | 수정은 제목(공백이면 `invalid_title`, **파일은 바뀌지 않음**), 태그, 노트, 본문, `updatedAt`만 바꾼다. `createdAt`은 유지. | 테스트: `update_text_drop_updates_metadata_note_content_tags_and_timestamp`, `update_text_drop_rejects_blank_title_and_leaves_files_unchanged` | 단위 | ☑ |
| S-14 | 이미지 Drop도 제목·노트·태그를 수정할 수 있고 이미지 파일은 그대로 둔다. | 테스트: `update_image_drop_updates_metadata_note_tags_and_keeps_image` | 단위 | ☑ |
| S-15 | Drop ID에 `/`, `\`, `..`가 있거나 비면 `invalid_drop_id`, 폴더가 없으면 `drop_not_found`. | `drop_folder_path` | 단위 | ☑ |
| S-16 | 삭제는 폴더 전체를 휴지통으로 이동. 이동 후에도 폴더가 있으면 `delete_failed`이고 목록에 남는다. | 테스트: `delete_helper_removes_drop_from_scan_when_trash_mover_succeeds`, `delete_helper_leaves_drop_when_trash_mover_fails` | 단위(이동 동작 주입) + 수동 | ☑ |
| S-17 | 저장 폴더 설정을 바꾸면 스캔과 저장이 새 폴더를 쓴다. | 테스트: `save_and_scan_use_configured_storage_root`, Swift `scanAndSaveUseTheFolderThatSettingsPointsAt`, `choosingAFolderSavesItKeepsOtherFieldsAndReloads` | 단위 | ☑ |
| S-18 | 읽는 중 `content.md`/이미지/`note.md` 하나가 실패해도 Drop은 남기고 해당 경고만 추가. | `read_drop_folder` | 단위 | ☑ |
| S-19 | `drops/`가 없으면 빈 목록(오류 아님). 저장 시에는 `drops/`를 만든다. | `scan_drops_from_root` | 단위 | ☑ |
| S-20 | 이미지 Drop은 `imagePath`가 없어도 `image.png`를 기본으로 본다. | `read_drop_folder` | 픽스처: `legacy-minimal-image` | ☑ |

## C. 설정

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| C-01 | 설정 파일 경로는 고정(`~/Library/Application Support/Notedrop/settings.json`)이고 저장 폴더 설정과 무관. | `settings.rs` | 단위 | ☐ |
| C-02 | 파일이 없으면 기본값을 만들어 저장. JSON이 깨지면 `settings_invalid`. | 테스트: `default_settings_use_default_storage_and_system_theme` | 단위·픽스처 | ☑ |
| C-03 | 부분 갱신: 보낸 필드만 바꾸고 나머지는 유지, `updatedAt` 갱신. | 테스트: `updating_settings_persists_path_first_run_theme_and_updated_at`, `updating_settings_persists_shortcuts_without_changing_unrelated_fields` | 단위 | ☑ |
| C-04 | `captureConfirmationMode` 키가 없으면 `modal`. 잘못된 값으로 갱신하면 거부. | 테스트: `missing_capture_confirmation_mode_defaults_to_modal`, `update_rejects_invalid_capture_confirmation_mode`, `changingCaptureModePersistsAndKeepsTheme` | 단위 | ☑ |
| C-05 | `paneWidths`는 읽고 쓸 때 180–320 / 300–560으로 고정, `recentTags`는 태그 규칙과 12개 제한. | 테스트: `updating_settings_persists_pane_widths_and_recent_tags` | 단위 | ☑ |
| C-06 | 단축키 문자열은 Tauri 문법(`Shift+Cmd+K`)으로 저장. Swift가 이 문자열을 파싱해야 하며 파싱 불가면 저장 거부. 파일은 바뀌지 않아야 한다. | 테스트: `update_rejects_unparseable_selected_text_shortcut`, `update_rejecting_invalid_shortcut_leaves_persisted_settings_file_untouched` | 단위(앱): `ShortcutModelTests`로 거절된 입력이 필드에 남지 않음 확인. 단위: 수식어(`Shift`, `Cmd`/`Command`, `Ctrl`/`Control`, `Alt`/`Option`)와 키 이름 | ☑ |
| C-07 | 원자적 쓰기(임시 파일 + 이름 변경)로 쓰고 쓰기 실패 시 임시 파일을 지운다. 동시 갱신은 직렬화. | `atomic_write_settings`, `SETTINGS_UPDATE_LOCK` | 단위 | ☐ |
| C-08 | 단축키 변경 순서: 새 것 등록 → 이전 것 해제 → 설정 저장. 어느 단계가 실패해도 이전 단축키가 살아 있어야 한다. | 테스트: `changing_selected_text_shortcut_replaces_the_old_registration`, `failed_registration_keeps_the_previous_shortcut_active`, `persistence_failure_restores_the_previous_shortcut` | 단위(가짜 등록기): `ShortcutControllerTests` (등록→해제→저장 순서, 등록 실패·저장 실패 롤백, 롤백 실패 `shortcut_rollback_failed`) + 수동(실제 충돌) | ☑ |
| C-09 | 시작 시 저장된 단축키 하나만 등록(다른 단축키는 등록하지 않음). 등록 실패는 보관 오류와 메뉴 막대 `Error`로 알린다. | 테스트: `startup_registers_only_the_selected_text_shortcut` | 단위: `ShortcutControllerTests.startupRegistersOnlyTheStoredShortcut` + 수동 | ☑ |
| C-10 | `theme`가 `system`이면 앱 외형을 시스템에 맡기고, `light`/`dark`는 시스템을 덮어쓴다. | `useTheme.ts`. Swift: `SettingsModel.colorScheme`, 테스트 `colorSchemeFollowsTheme`, `changingThemePersistsAndKeepsOtherFields` | 단위(모델) + 수동(창 외형) | ☑ |
| C-11 | 읽은 `theme`이 잘못되면 `system`으로 보정, `storageFolderPath`가 공백이면 기본 폴더. | `read_app_settings_from_path` | 단위 | ☑ |
| C-12 | 번들 ID를 바꾸면 손쉬운 사용·자동화 권한을 새로 허용해야 한다. 설정과 Drop은 영향이 없다. | — | 수동 | ☐ |

## P. 캡처 (선택 텍스트)

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| P-01 | 출처 수집이 선택 텍스트 읽기(접근성·클립보드 폴백 모두)보다 **먼저**. 앞 앱은 캡처 시작 때 한 번만 정하고 출처 수집과 선택 읽기가 같은 앱을 쓴다(STA-50). | 테스트: `selected_text_capture_collects_source_first_and_restores_text_and_image`, `frontmostAppIsResolvedOnceAndSharedByCollectorAndReader` | 단위(호출 순서) | ☑ |
| P-02 | **(폴백 경로)** 복사 후 대기: 변경 횟수가 달라질 때까지 25 ms 폴링, 최대 700 ms. | `SELECTED_TEXT_COPY_TIMEOUT`, `POLL_INTERVAL` | 단위·수동 | ☐ |
| P-03 | **(폴백 경로)** 복사한 텍스트가 이전 클립보드와 같아도 변경 횟수가 달라졌으면 성공. | 테스트: `selected_text_capture_accepts_text_that_matches_the_previous_clipboard` | 단위 | ☑ |
| P-04 | **(폴백 경로)** 시간 초과, 빈 선택, 읽기 실패, 복사 시뮬레이션 실패 **모두에서** 이전 클립보드를 복원한다. 단, 변경 횟수가 그대로면(복사가 일어나지 않았으면) 클립보드를 다시 쓰지 않는다. 다시 쓰면 파일·RTF·여러 항목이 텍스트와 PNG로 줄어든다. | 테스트: `selected_text_capture_restores_clipboard_after_copy_timeout`, `…_after_empty_selection`, `…_after_read_failure`, `…_when_copy_shortcut_fails` | 단위 | ☑ |
| P-05 | **(폴백 경로)** 복원 실패는 캡처 실패가 아니라 경고(`clipboard_restore_failed`)가 붙은 성공. | 테스트: `selected_text_is_returned_with_a_warning_when_restore_fails` | 단위 | ☑ |
| P-06 | **(폴백 경로)** 백업이 실패해도(경고 `clipboard_backup_failed`) 캡처는 계속하고 복원을 시도한다. | 테스트: `selected_text_capture_attempts_restore_when_backup_fails` | 단위 | ☑ |
| P-07 | 선택된 텍스트가 없으면 `no_selected_text`(공백뿐인 텍스트 포함). 끝의 `\r`/`\n`은 제거. | `trimmed_capture_text` | 단위 | ☑ |
| P-08 | 자동화·접근성 오류는 `permission_missing`으로 바꾸고 손쉬운 사용 권한 안내를 붙인다. | `capture_selected_text_with` | 수동: 권한 없이 실행 | ☑ |
| P-09 | **(폴백 경로)** 백업 대상은 텍스트와 PNG 이미지. 이미지는 PNG로 정규화해 보관·복원한다. 복원은 텍스트와 이미지를 한 항목으로 쓴다. | `write_clipboard_snapshot` | 수동: 이미지만/텍스트만/둘 다 있던 클립보드 | ☑ |
| P-10 | 결과 Draft는 `note` 없음, `tags` 빈 배열. | `capture_selected_text_with` | 단위 | ☑ |
| P-11 | `modal`이면 팝업, `instant`이면 텍스트만 즉시 저장(노트 `""`, 태그 없음). | `instant_save_payload_from_draft`, `handle_capture_draft` | 단위: `CaptureConfirmationTests`, `CaptureRouterTests`(`instantTextIsSavedWithAnEmptyNoteAndNoTags`, `theModeIsReadAtEveryCapture`) + 수동 | ☑ |
| P-12 | `instant`에서도 이미지·`mixed`는 팝업. (도구 막대 캡처 버튼은 D-05 결정으로 만들지 않는다.) | `handle_capture_draft` | 단위: `instantStillOpensThePopupForImagesAndMixedContent`, `instantImageAndMixedOpenThePopupAndSaveNothing` + 수동 | ☑ |
| P-13 | 선택 텍스트 캡처 실패: 오류 보관 + 메인 창 표시 + 메뉴 막대 `Error`. 보관 오류는 메인 창에서 **한 번만** 소비. | `emit_selected_text_capture_event`, 테스트: `pending_capture_error_is_returned_once` | 단위·수동 | ☐ |
| P-14 | 별도 팝업 창이 이미 열려 있으면 단축키는 새 캡처를 하지 않고 열린 팝업을 앞으로 가져온다(결정 STA-47). 팝업이 열려 있으면 최전면 앱이 Notedrop 자신이라 선택 텍스트를 읽을 수 없기 때문이다. 레거시의 "새 Draft로 교체"와 다르다. | `open_capture_window` | 수동: 팝업을 연 채 단축키 재입력 | ☑ |
| P-15 | 레거시는 클립보드 접근을 `swift -e` 서브프로세스로 했다. Swift 앱은 `NSPasteboard`를 직접 쓰므로 이 구조는 이어받지 않는다(같은 시맨틱만 유지). | `capture.rs` | — | ☐ |
| P-16 | 접근성 읽기(`AXUIElementCreateApplication(최전면 앱)` → 포커스 요소 → `AXSelectedText`)가 비어 있지 않은 값을 주면 클립보드를 읽거나 쓰지 않고, `Cmd+C`도 보내지 않는다. 시스템 전역 요소는 쓰지 않는다(Chrome에서 실패). | [ax-probe.md](ax-probe.md) | 단위(가짜 호출 기록) + 수동: 메모·Chrome에서 캡처 전후 클립보드 `changeCount` 동일 | ☑ |
| P-17 | 접근성 읽기가 실패하거나 값이 비거나 공백뿐이면 클립보드 폴백(P-02~P-09)으로 넘어가며, 그 자체로 `no_selected_text`로 보지 않는다. 최전면 앱이 Notedrop이면 접근성 읽기를 건너뛴다. | [ax-probe.md](ax-probe.md) | 단위 + 수동: Safari·터미널(Hyper)에서 폴백으로 저장 | ☑ |

## K. 클립보드 캡처 (메뉴 막대 `Save Clipboard...`)

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| K-01 | 변경 횟수를 읽기 전후로 비교해 다르면 `clipboard_changed`. | 테스트: `ClipboardCaptureTests.rejectsContentChangedDuringRead`, `acceptsAnUnchangedCountAndAnUnreportedCount` | 단위 | ☑ |
| K-02 | 분류: 텍스트만 `text`, 이미지만 `image`, 둘 다 `mixed`, 둘 다 없으면 `clipboard_empty`. | 테스트: `textOnlyBecomesATextDraft`, `mixedContentKeepsBothForThePopupToChooseFrom`, `imageOnlyBecomesAnImageDraft`, `imageFromNotedropHasNoSourceAndTheFallbackTitle`, `emptyOrBlankClipboardFailsAsEmpty`; 팝업에서 고른 유형만 저장: `SavePopupImageTests` | 단위 | ☑ |
| K-03 | 이미지 디코딩 실패 시 텍스트가 있으면 텍스트로 진행하고 경고 `clipboard_image_unavailable`. 텍스트도 없으면 그 오류로 실패. | 테스트: `undecodableImageFallsBackToTextWithAWarning`, `undecodableImageWithoutTextFails`, `readFailureIsReportedAsUnavailable` | 단위 | ☑ |
| K-04 | 이미지는 PNG가 있으면 PNG, 없으면 TIFF를 PNG로 변환해 사용. | `read_clipboard_snapshot` | 수동: 스크린샷(PNG)과 TIFF를 내는 앱 | ☑ |
| K-05 | 최전면 앱이 Notedrop이면 출처를 비우고 제목을 다시 추론. 다른 앱이면 출처 유지. | 테스트: `omitsNotedropAsSourceAndReinfersTheTitle`, `keepsTheSourceOfAnotherApp` | 단위 | ☑ |
| K-06 | 클립보드 캡처 실패는 오류 보관 + 메뉴 막대 `Error`만(메인 창을 띄우지 않음). | `CaptureRuntime.reportQuietly`(Error만 표시하고 오류를 보관, 메인 창은 띄우지 않음) | 수동 | ☑ |

## M. 출처 수집

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| M-01 | 최전면 앱 이름과 앞 윈도우 제목. 제목을 못 얻어도 앱 이름은 유지. | `collect_source_metadata` | 수동 | ☑ |
| M-02 | 앱이 `Google Chrome`일 때만 활성 탭 URL을 시도. 실패는 경고 `chrome_url_failed`, 앱·윈도우 실패는 `metadata_failed`. | 위와 같음 | 수동: 권한 거부 상태 | ☑ |
| M-03 | 출처 수집 실패는 저장을 막지 않는다. 비어 있는 필드는 `null`로 저장. | PRD "Source metadata" | 단위 | ☐ |
| M-04 | 파일 경로는 레거시가 수집하지 않는다. 신뢰할 수 있는 API가 없으면 비워 둔다. | `collect_source_metadata` | — | ☐ |

## A. 권한

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| A-01 | 손쉬운 사용: `AXIsProcessTrusted`. 없으면 System Settings > Privacy & Security > Accessibility 안내. | `permissions.rs` | 수동 | ☑ |
| A-02 | 클립보드: 텍스트를 읽을 수 있으면 허용, 읽기 실패면 없음, 확인 불가면 알 수 없음. | `permissions.rs` | 수동 | ☑ |
| A-03 | 자동화: 항상 `알 수 없음`. Chrome이 최전면일 때만 시스템이 묻는다는 안내. `Info.plist`에 `NSAppleEventsUsageDescription` 필요. | `permissions.rs` | 수동 | ☑ |
| A-04 | 권한이 없어도 앱이 종료되지 않고 UI에 이유를 보여 준다. | PRD "macOS permissions" | 수동 | ☑ |

## L. Library

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| L-01 | 검색은 제목·본문·노트·이미지 경로·앱·윈도우·URL·태그의 부분 문자열(대소문자 무시). 이미지 경로(`image.png`)로도 검색된다. | `drop-utils.ts` `matchesDropSearch` | 단위 | ☑ |
| L-02 | 기간 필터: 오늘은 같은 달력 날짜, 7·30일은 `createdAt ≥ 지금 − N일`. 날짜를 해석할 수 없는 Drop은 기간 필터에서 제외. | `matchesDateFilter` | 단위 | ☑ |
| L-03 | 날짜 그룹: 오늘/어제/지난 7일(2~7일 전)/이전. 해석 불가한 날짜는 `이전`. 빈 그룹 숨김. | `drop-groups.ts` | 단위 | ☑ |
| L-04 | 선택이 필터 결과에서 사라지면 첫 항목, 결과가 비면 선택 없음. | `useLibraryFilters.ts` | 단위 | ☑ |
| L-05 | 사이드바 선택은 항상 하나. 유형 선택은 태그 필터를 지우고 태그 선택은 유형을 `all`로 돌린다. 필터 지우기는 앱·기간만 지운다. | `Sidebar.tsx`, `useLibraryFilters.ts`(STA-37) | 단위 | ☑ |
| L-06 | 사이드바 접힘은 Library↔Settings 전환과 창 크기 변경을 지나도 유지. 두 화면에서 사이드바 너비·모양이 같다. | `MainWindow.tsx`(STA-38) | 수동 | ☑ |
| L-07 | 인스펙터 오버레이: 같은 토글 또는 Escape로 닫고 Drop 목록으로 포커스 복귀(D-13). 검색 편집 중 Escape는 검색을 먼저 닫는다. | `docs/design/sta30-font-book/README.md` | 수동 | ☑ |
| L-08 | 검색을 닫아도(Escape) 검색어와 결과 유지. 지우기는 전체 복원. `Cmd+F`는 검색 포커스. | `design-system.md` | 수동 | ☑ |
| L-09 | 새로고침은 디스크를 다시 스캔한다. 다른 곳(팝업 창 등)의 저장 신호를 받아도 다시 스캔한다. | `useLibraryRefreshEvent.ts` | 수동 | ☑ |
| L-10 | Save Popup에서 저장하면 Library가 새로고침되고 새 Drop이 선택된다. | `handleCaptureSaved` | 단위(`LibraryModel`) + 수동 | ☑ |
| L-11 | 목록 우클릭 메뉴: 출처 열기(URL 있을 때), 내용 복사(텍스트일 때), Markdown 내보내기, 구분선, 휴지통. 우클릭하면 그 행을 먼저 선택. | `LibraryPane.tsx` | 수동 | ☑ |
| L-12 | `Cmd+Backspace`는 삭제 확인 시트, 확인 후에만 휴지통으로 이동. | `LibraryPane.tsx`, `DeleteConfirmationSheet.tsx` | 수동 | ☑ |
| L-13 | 출처 열기: URL이 비어 있으면 `source_url_missing`. 버튼은 URL이 없을 때 비활성. | `commands.rs` `open_source_url` | 단위·수동 | ☑ |
| L-14 | Markdown 내보내기: 취소하면 파일을 쓰지 않는다. 형식은 spec 7장. | `markdown.rs`, 테스트: `markdown_generation_includes_drop_fields` | 단위 | ☑ |
| L-15 | 창 크기 때문에 줄어든 표시 너비를 `paneWidths`에 저장하지 않는다. 구분선 조절이 끝났을 때만 저장. | `MainWindow.tsx` | 수동 | ☑ |

## E. 편집

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| E-01 | 편집 600 ms 후 자동 저장, 입력을 떠날 때 즉시 저장. | `useDropAutoSave.ts` | 단위(가짜 타이머) | ☑ |
| E-02 | 저장 중에 더 새로운 편집이 들어오거나 다른 Drop으로 이동했으면 늦게 온 응답을 반영하지 않는다(편집 내용을 덮어쓰지 않음). | `useDropAutoSave.ts` revision/dropRef | 단위 | ☑ |
| E-03 | 변경이 없으면 저장하지 않고 상태만 `saved`로 정리. | `useDropAutoSave.ts` | 단위 | ☑ |
| E-04 | 제목이 공백이면 저장하지 않고 `blankTitle` 오류. 저장 실패 상태에서는 blur가 재시도하지 않고 `다시 시도` 버튼으로만 재시도. | `useDropAutoSave.ts`, `DropDetailPane.tsx` | 단위 | ☑ |
| E-05 | 패널을 접거나 오버레이를 열고 닫아도 편집 중인 노트·태그 초안을 잃지 않는다(편집기를 다시 만들지 않는다). | `design-system.md` | 수동 | ☑ |
| E-06 | 편집 후 목록에 즉시 반영하되 선택은 유지한다. | `useDropActions.ts` | 수동 | ☑ |

## I. 입력

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| I-01 | **한글 입력기 조합 중 Enter/쉼표로 태그를 등록하지 않는다.** | `DropDetailPane.tsx` `isComposingKey`, `SavePopover.tsx` | 수동: 한글로 태그 입력 후 Enter(조합 확정 Enter는 등록 아님) | ☑ |
| I-02 | 태그 입력은 Enter 또는 쉼표로 등록, 여러 개를 쉼표로 한 번에. 이미 있는 태그는 안내(`tagAlreadyAdded`)하고 중복 추가 안 함. | `DropDetailPane.tsx` `registerTags` | 단위 | ☑ |
| I-03 | 태그 칩 삭제 후 입력창에 포커스. | `removeTag` | 수동 | ☑ |
| I-04 | 팝업 `Cmd+Enter` 저장(저장 중이면 무시), Escape 취소. 레거시는 `Cmd+Enter`에서 입력기 조합 여부를 검사하지 않는다(조합 중에도 동작). | `SavePopover.tsx` | 수동 | ☑ |
| I-05 | 포커스 링은 컨트롤 모양을 따르는 둥근 링이고 레이아웃을 밀지 않는다. 컨테이너에는 링이 없다. 목록 행은 안쪽 링. | STA-38 CSS(실제 앱 미검증) | 수동 | ☐ |
| I-06 | 제목 인라인 이름 변경: Return 확정, Escape 되돌림, 둘 다 포커스를 목록에 돌린다. | STA-38(실제 앱 미검증) | 수동 | ☑ |

## T. 메뉴 막대

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| T-01 | 템플릿 아이콘, 툴팁 `Notedrop`, 좌클릭은 메뉴가 아니라 메인 창 열기. 메뉴는 좌클릭이 아닌 방식(우클릭)으로 연다. | `tray.rs` | 수동 | ☑ |
| T-02 | 메뉴 항목 ID는 `save-clipboard`, `open-library`. 알 수 없는 ID는 무시. | 테스트: `routes_stable_tray_menu_ids`, `save_clipboard_menu_action_starts_clipboard_capture` | 단위 | ☑ |
| T-03 | 성공 `Saved`, 실패 `Error`를 900 ms 동안 제목과 툴팁에 표시하고 원복. | `show_feedback` | 단위: `MenuBarTests`(`errorShowsFor900msThenRestores`, `savedShowsFor900msThenRestores`) + 수동 | ☑ |
| T-04 | 메인 창을 열 때 보관된 캡처 오류를 확인하도록 신호를 보낸다. | `show_main_window` | 수동 | ☐ |

## N. 지역화

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| N-01 | 시스템 언어가 `ko`로 시작하면 한국어, 아니면 영어. | `i18n.tsx` `resolveLocale` | 단위 | ☑ |
| N-02 | 두 언어의 키 집합이 같다(한쪽에만 있는 문구 없음). | `i18n.tsx` `Dictionary` 타입 | 단위 | ☑ |
| N-03 | 알려진 오류 코드는 지역화한 문구로, 그 밖에는 `defaultError`. (레거시는 그 밖의 코드를 원본 메시지로, 문자열 오류를 그대로 보여 줬다. Swift는 `detail`이 로그용이라 의도적으로 다르게 간다. 아래 STA-61 기록 참고.) | `translateError` | 단위 | ☑ |
| N-04 | 권한 상세 문구는 항목×상태(허용/없음)로 키가 있고, `알 수 없음`은 `permissionUnknownDetail`. | `permissionDetail` | 단위 | ☑ (`PermissionsModelTests.detailKeysFollowItemAndStatusAndUnknownIsShared`, `everyDetailAndStatusKeyHasBothLanguages`) |

## D. 결정이 필요한 차이와 알려진 공백

레거시에서 확인되지 않았거나 문서와 구현이 어긋난 곳입니다. 구현 전에 결정하거나 확인해 기록하세요.

| ID | 상황 | 제안 | 결정 | ☐ |
| --- | --- | --- | --- | --- |
| D-01 | PRD는 `Shift+Cmd+V`(클립보드 캡처)를 요구하지만 구현된 적이 없다. 클립보드 캡처는 메뉴 막대의 `Save Clipboard...`뿐이다. | 먼저 레거시와 같게 메뉴만 구현. 단축키는 별도 요청이 있을 때. | | ☐ |
| D-02 | 타입에 `mixed`가 있지만 **저장되는 Drop은 `text` 또는 `image`뿐**이다(`mixed` Draft는 팝업에서 하나를 고른다). 레거시는 `mixed` Drop을 목록에는 보여 주지만 본문과 이미지를 읽지 않는다(픽스처로 확인). | 최소한 레거시와 같게(깨지지 않고 목록에 표시). 본문·이미지 표시는 별도 결정. | | ☐ |
| D-03 | 레거시 단축키 문자열은 Tauri 문법이다. 전체 허용 범위(예: 방향키, 펑션키, `CmdOrCtrl`)는 문서화되어 있지 않다. | 최소 `Shift/Cmd/Ctrl/Alt` + 문자·숫자·펑션키를 지원하고 나머지는 거부. | | ☐ |
| D-04 | 이미지 Drop의 `image.png`가 아닌 다른 `imagePath`를 읽는 경로는 있으나(`drop.imagePath`) 쓰는 경로는 항상 `image.png`다. | 읽기는 `imagePath` 우선, 쓰기는 `image.png`. | | ☐ |
| D-05 | 도구 막대 `선택한 텍스트 캡처`는 Notedrop이 최전면일 때 Notedrop 안의 선택 텍스트만 캡처한다(다른 앱의 선택을 가져오지 못한다). | 기능을 만들지 않는다. | **결정(STA-47): 제거.** 트리거는 전역 단축키뿐. 문구 `captureSelected`도 제거. | ☑ |
| D-06 | 이름 바꾼 단축키가 다른 앱과 충돌해 등록에 실패할 때의 사용자 메시지(`shortcut_registration_failed`)가 레거시에서는 영어 원문이다. | 한국어 문구 추가. | **결정(STA-55): 한국어·영어 문구 `shortcutRegistrationFailed` 추가.** | ☑ |
| D-07 | 메인 창을 닫았을 때 앱이 종료되는지, 메뉴 막대에 남는지가 레거시에서 확인되지 않았다. 메뉴 막대와 전역 단축키의 목적상 남는 편이 자연스럽다. | 메뉴 막대에 남는다. 마지막 창을 닫아도 종료하지 않고 전역 단축키와 메뉴 막대 항목을 유지한다. 종료는 Cmd+Q. (STA-52) | | ✔ |
| D-08 | 로그인 시 자동 실행, Dock 아이콘 표시 여부는 정의되어 있지 않다. | 범위 밖. 필요하면 새 이슈. | | ☐ |
| D-09 | `Design.md`와 `design-system.md`의 일부 문장은 AppKit 도구 막대, `compactSearch`, `inspectorOverlay` 같은 Tauri 구현 용어를 쓴다. | Swift 구현이 안정되면 문서에서 해당 구현 용어를 제거. | | ☐ |
| D-10 | STA-38에서 도입한 SF Symbols 렌더링, 포커스 링, 제목 인라인 이름 변경, 목록 비포커스 선택 약화, 설정 화면 토글은 **실제 앱에서 확인되지 않았다.** | 레거시 앱에서 확인하지 말고 Swift 구현에서 기준(서체관리자)으로 직접 확인. | | ☐ |
| D-11 | 라이트 테마의 도구 막대와 960 pt 너비 실화면 확인이 남아 있다. | Swift 구현에서 확인. | | ☐ |
| D-12 | 문구 `shortcutFormatHint`가 "Tauri 형식"이라고 안내한다. 저장 문자열은 호환을 위해 같은 형식(`Shift+Cmd+K`)을 쓰지만 사용자에게 구현 용어를 보이면 안 된다. | 문구에서 Tauri를 빼고 형식 예시만 안내. | **결정(STA-55): `shortcutFormatHint`를 "수식키와 키를 +로 연결, 예: Shift+Cmd+K, F21–F24 미지원"으로 교체.** | ☑ |

## 4단계 수동 확인 기록 (STA-47, 2026-10-08)

실제 앱(`make-app.sh debug` 번들, 저장 폴더·설정 파일은 `/tmp`로 분리)에서 확인한 범위입니다. 일부만 확인한 항목은 ☐로 두었습니다.

| 확인한 내용 | 결과 | 관련 항목 |
| --- | --- | --- |
| 메모에서 선택 후 `Shift+Cmd+C` → 팝업 → 노트·태그 입력 → 저장 | 정상. `drop.json` 키 집합과 `null` 규칙, `content.md`, `note.md`, `recentTags` 갱신, 출처(앱·윈도우 제목) 확인 | P-10, M-01, S-01, I-02 |
| Safari 본문 선택(접근성 읽기 불가 → 폴백) → 팝업에 선택 텍스트 → 저장·취소 후 붙여넣기 | 정상. 캡처 전 클립보드 텍스트가 그대로 복원됨 | P-17, P-04(성공 경로), P-09(텍스트만) |
| 권한을 초기화한 뒤 다시 허용 | 같은 번들 ID의 레거시 Tauri 앱이 있으면 이전 허용 항목과 새 빌드 서명이 맞지 않아 권한이 없다고 나올 수 있음. `tccutil reset Accessibility app.notedrop.dev` 후 재허용 | C-12, A-01 |

이어서 사용자가 목록의 나머지 수동 항목(메모에서 클립보드 불변, Chrome URL, 선택 없음, 권한 해제, 팝업이 열린 채 단축키,
한글 조합 중 Enter, 터미널 폴백)이 모두 동작한다고 보고했습니다. 항목별 출력은 남기지 않았고 사용자 보고에 근거합니다.

**범위 밖으로 확인된 것**: 이미지, 텍스트와 이미지가 함께 있는 클립보드의 **저장**은 4단계 범위가 아닙니다. 선택 텍스트 캡처는
텍스트 Drop만 만들고(스펙 3.1), 이미지와 `mixed`는 클립보드 캡처(스펙 3.2, K-01~K-06, 메뉴 막대 `Save Clipboard...`)와 팝업의
이미지 미리보기·유형 선택이 필요해 5단계에서 구현합니다(STA-47에서 확정). 이미지가 들어 있던 클립보드를 텍스트 캡처 뒤에
복원하는 동작(P-09)은 이번에 따로 확인하지 않았습니다.

## 호환성 검증 절차

1. [픽스처](fixtures/README.md)의 폴더를 임시 저장 폴더로 복사하고 설정의 `storageFolderPath`를 그 폴더로 지정한다.
2. 앱을 실행해 모든 Drop이 표시되는지(깨진 것은 경고만) 확인한다.
3. 각 Drop을 수정하고 저장한 뒤 `drop.json`의 키 집합과 `null` 규칙(S-01)이 유지되는지 확인한다.
4. 새 Drop을 저장해 ID, 시각, 파일 구성이 S-05~S-11을 만족하는지 확인한다.
5. 실제 사용자 폴더로는 먼저 **복사본**에서 같은 확인을 반복한다. 원본 폴더를 처음부터 쓰지 않는다.

## 부분 확인 (STA-41)

- S-16: 휴지통 이동 주입으로 성공·실패 단위 테스트만 확인했습니다. 실제 `FileManager.trashItem` 동작은 수동 확인이 남아 있습니다.
- C-01: 고정 경로 계산(`SettingsStore.defaultFileURL`)은 구현했지만 테스트하지 않았습니다.
- C-04: 설정 갱신 API가 열거형이라 잘못된 값은 컴파일 단계에서 막힙니다. 읽을 때의 거부만 테스트했습니다.
- C-07: `Data.write(.atomic)`(임시 파일 + 이름 변경)를 쓰며 fsync는 하지 않습니다. 쓰기 실패 시 임시 파일 정리는 테스트하지 않았습니다.

## 2단계 확인 결과 (STA-42)

확인함(창 캡처, 앱 번들 실행): 사이드바 접힘이 Library↔설정 전환 뒤에도 유지(L-06), 사이드바 단일 선택(L-05, 모델 테스트 포함), 960 pt에서 검색 아이콘 축약·아이콘 클릭으로 필드 열림, 1176 pt 미만에서 인스펙터가 오버레이로 열리고 Escape로 닫힘, 라이트 테마 960 pt.

후속 STA-43에서 처리했습니다. 결과는 아래 섹션에 있습니다.

## 서체관리자 시각 일치 결과 (STA-43)

- 원인: SwiftPM이 바이너리의 SDK 버전을 배포 대상(14.0)으로 기록해 macOS 26이 이전 창 스타일을 적용했다. `scripts/make-app.sh`가 `vtool`로 실제 SDK 버전을 다시 기록한다.
- 결과: 떠 있는 둥근 사이드바, 캡슐로 묶인 도구 막대 버튼, 도구 막대의 제목·개수(`navigationTitle`/`navigationSubtitle`)가 서체관리자와 같다. 다크 테마 1300 pt 창으로 확인했다.
- 앱 번들에 `CFBundleLocalizations`(en, ko)를 선언해 시스템이 붙이는 문구(사이드바 가리기, 접근성 역할 이름)도 한국어로 나온다.

### 동작 확인 (실제 키·마우스 이벤트, 1300/1000/960 pt)

- L-15: 구분선을 마우스로 끌었을 때만 `paneWidths`를 저장한다(버튼이 눌린 상태 + 창 너비 변화 없음, 400 ms 뒤 한 번). 실행 직후 레이아웃 정착, 창 크기 변경, 사이드바 접기는 저장하지 않는다. 960 pt에서 목록이 390 → 339로 줄어도 저장 값은 390이다. 다시 실행하면 settings.json 값으로 복원한다.
  - SwiftUI가 `ideal` 열 너비를 무시하므로 창이 열릴 때 NSSplitView 구분선 위치를 직접 설정한다(`SplitViewRestorer`). AppKit의 자체 자동 저장(`NSSplitView Subview Frames …`)은 줄어든 너비를 복원하므로 실행 시 지운다.
  - 본문 최소 너비 360을 지정해, 창을 줄일 때 목록이 300 아래로 밀리지 않게 했다.
  - 구분선의 접근성 값은 AppKit 기본(`splitter, Value`)으로 노출된다.
- L-08: `Cmd+F`가 모든 너비에서 검색 필드로 포커스한다(이전에는 좁은 창에서만 동작). Escape로 닫아도 검색어와 결과를 유지한다. AppKit은 Escape 때 필드를 비우므로, 현재 이벤트가 Escape 키일 때 빈 값을 무시한다. 지우기 버튼(실제 클릭)은 전체 목록을 복원한다.
- L-07: 오버레이와 검색이 함께 열려 있을 때 첫 Escape는 검색만, 두 번째 Escape는 오버레이를 닫는다. 좁은 창의 `Cmd+F`는 필드가 생긴 다음 턴에 포커스를 요청한다.
- 설정 화면: 검색 필드와 검색 아이콘을 숨기고 `Cmd+F`를 비활성화한다.

### 결정

- D-13 (L-07 변경, 확정 · 재검토는 STA-44): 오버레이를 닫으면 포커스를 토글이 아닌 Drop 목록으로 돌린다. macOS 도구 막대 버튼은 '전체 키보드 접근'이 꺼져 있으면 키보드 포커스를 받지 않으므로, 토글로 돌려주면 포커스가 사라진다.
- D-14 (구분선 키보드 조절 없음, 확정 · 재검토는 STA-44): 좌우 화살표 8 pt 조절은 구현하지 않는다. NSSplitView와 서체관리자 모두 키보드 조절을 제공하지 않으며, 웹뷰 시절 요구였다. 접근성 값은 AppKit 기본으로 제공된다.
- D-15 (`.inspector` 대신 HStack): 인스펙터는 고정 280 pt(design-system)이라 크기 조절 손실이 없다. 인스펙터 내용은 일반 SwiftUI 뷰라 접근성 트리와 Tab 이동은 같다. 잃는 것은 시스템 인스펙터의 전체 높이 열 배치와 기본 전환 애니메이션이며, 1176 pt 미만은 어차피 직접 만든 오버레이를 쓴다. 시작 시 종료 문제가 없는 현재 방식을 유지한다.
- D-16 (Xcode 프로젝트): 지금은 만들지 않는다. SwiftPM + `make-app.sh`로 빌드·테스트·번들이 된다. 4단계에서 접근성 권한(TCC)을 쓰면, 빌드마다 바뀌는 ad-hoc 서명 때문에 권한이 초기화된다. 그때 고정 서명 ID나 Xcode 프로젝트 도입을 다시 판단한다.
- 남음: `orca computer`의 접근성 누르기로 검색 지우기 버튼을 누르면 필드만 비고 결과가 남는다(실제 클릭은 정상). VoiceOver 사용자 경로라 4~6단계 접근성 점검 때 다시 본다.

## 3단계 확인 결과 (STA-46)

- 단위 테스트(`DropEditorTests`, `LibraryEditingTests`): 600 ms 디바운스, 필드를 떠날 때 즉시 저장, 변경 없으면 저장 안 함, 공백 제목 `blankTitle`, 실패 후 blur 재시도 없음·`다시 시도`·새 편집으로 재개, 늦게 온 응답 무시, Drop 전환 시 이전 편집 저장, 새로 고침 시 초안 유지, 태그 규칙·중복, 삭제 성공·실패(이동 실패와 폴더 잔존), 내보내기 내용·실패. 시계는 가짜 시계(`ManualClock`)다.
- 실제 앱(저장소 복사본, 실제 키·마우스 이벤트): 노트 편집이 `note.md`에 저장되고 목록·사이드바 태그 목록이 즉시 갱신되며 선택이 유지됨(E-06). 태그 Return·쉼표 등록, 중복 시 `이미 추가됨`(I-02). 제목 Return 확정·Escape 되돌림·포커스는 목록으로(I-06). 삭제는 확인 시트 → 취소는 변경 없음, 확인은 폴더 이동·알림·다음 Drop 선택(S-16). 내보내기 저장 대화상자는 기본 파일명 `{slug}.md`이고 취소하면 쓰지 않는다. 오버레이를 닫았다 열어도 태그 입력 초안이 남는다(E-05).
- I-01 (한글 입력기, 실제 한글 2벌식으로 확인): 조합 중인 글자 뒤의 첫 Return·쉼표는 조합만 확정하고 태그를 등록하지 않으며, 두 번째 Return에서 등록된다. 한글이 없는 입력("1" 다음 Return)은 바로 등록된다. 확정 뒤 남은 쉼표는 다음 글자를 삼키지 않는다. 한글 2벌식은 AppKit 필드에서 조합 중인 글자를 임시 텍스트로 두지 않고 직접 삽입하며 확정 Return을 앱에도 넘기므로 `hasMarkedText`로는 알 수 없다. 키 이벤트를 따라가는 `CompositionGuard`(확정 키 이후 글자를 입력했고 필드 끝이 한글이면 조합 중)로 구현했고 단위 테스트가 있다. 일본어·중국어 입력기는 확인하지 않았다(임시 텍스트를 쓰므로 `hasMarkedText` 경로가 처리할 것으로 본다).
- 한계: 접근성 기능으로 값만 바꾸는 입력은 바인딩을 갱신하지 않아 실제 키 입력으로만 검증했다. 종료 직전 저장은 키 입력 직후 종료 요청으로 한 번 확인했고, 600 ms 디바운스만으로 저장된 경우와 구분하지는 못했다(단위 테스트의 `drain` 시나리오가 경로를 검증한다).
- 구조: Drop마다 편집 슬롯(초안·저장본·상태·리비전)을 두고, 모든 쓰기를 하나의 순서 있는 큐로 보낸다. Drop을 바꿔도 편집은 백그라운드로 저장되고, 실패하면 슬롯이 남아 알림을 띄우며 다시 선택하면 복원된다. 종료 시 `applicationShouldTerminate`가 `drain`을 기다리고, 저장 실패면 첫 종료 요청은 취소하고 경고한다(15초 안에 다시 요청하면 종료).
- 리뷰: Codex로 3회 진행했다. 1회차 7건(겹친 저장, 전환 시 실패 유실, 종료 직전 유실, 제목 입력 중 응답, 필터 중 선택 이동, 내보내기 오래된 값, 태그 blur 저장), 2회차 5건(슬롯 소유권 문제 전반, 종료·내보내기·제목 blur 재시도), 3회차 4건(전환 시 제목 유실, 오래된 종료 경고, 저장 중 대기한 blur의 재시도, 남은 쉼표)을 모두 반영하고 각각 테스트를 추가했다.
- 최근 태그(`recentTags`)는 캡처 저장 후에만 갱신한다(스펙 1.5). 편집으로는 바꾸지 않는다.

## 5단계 설정 화면 기록 (STA-51)

단위 테스트(`SettingsModelTests`, 8개)로 확인함: 저장된 테마·저장 확인 방식을 읽음, 테마·방식 변경이 해당 필드만 바꿈(C-03), 쓰기 실패 시 선택을 되돌리고 안내, `system`은 재정의 없음·`light`/`dark`는 강제, 버전 표시 대체값.

수동 확인이 남음(실제 앱): 테마 변경이 메인 창과 Save Popup에 즉시 적용되고 `system`으로 돌아가면 풀리는지(C-10), 재실행 후 유지, 설정 화면에서 사이드바 접힘·너비가 Library와 같은지(L-06). `NOTEDROP_APPEARANCE`는 테마가 `system`일 때만 적용되는 개발용 재정의로 남겨 둠.


## 5단계 클립보드 캡처 기록 (STA-56)

메뉴 막대 `Save Clipboard...`로 텍스트 클립보드를 캡처한다. K-01, K-02, K-03, K-05는 단위 테스트(`ClipboardCaptureTests`)로 확인함. 이미지와 `mixed` 저장은 STA-57에서 들어왔다(아래 기록).

수동 확인이 남음(실제 앱): K-06(실패 시 `Error`만 보이고 메인 창이 뜨지 않음), 메뉴 항목에서 팝업이 열리고 저장되는지, Notedrop이 앞일 때 출처가 비는지.

## 5단계 저장 폴더와 첫 실행 기록 (STA-53)

설정 화면에 저장 폴더 경로와 `저장 폴더 선택` 버튼이 있다. 폴더를 바꾸면 `storageFolderPath`만 바뀌고 기존 Drop은 옮기지 않으며, 이후 스캔과 저장은 설정을 매번 읽어 새 폴더를 쓴다(S-17). 바꾸기 직전에 편집 중인 내용을 먼저 저장하고, 바꾼 뒤 Library를 다시 스캔한다. 선택을 취소하면 `folderCancelled` 안내가 나온다.

첫 실행(`hasCompletedFirstRun == false`)에는 닫을 수 없는 모달이 뜬다. `기본 폴더 사용`은 폴더를 만들고 `folderConfirmed`, `폴더 선택`은 선택한 폴더를 저장하고 `folderSet`을 보인 뒤 `hasCompletedFirstRun = true`로 저장한다. 선택을 취소하거나 폴더를 쓸 수 없으면 모달이 남는다.

폴더 판정(`StorageFolderCheck`): 폴더가 있으면 디렉터리이고 쓸 수 있어야 한다. 없는 폴더는 가장 가까운 상위 폴더가 쓸 수 있을 때만 통과한다(저장 때 `drops/`가 만들어지므로). 통과하지 못하면 설정 화면에 `storageFailure`를 보이고, 저장 팝업의 저장도 같은 판정으로 막는다.

개발용 `NOTEDROP_STORAGE_FOLDER`는 설정보다 우선한다. 폴더 변경을 확인하려면 이 변수 없이 `NOTEDROP_SETTINGS_FILE`만 지정해 실행한다. `NOTEDROP_SETTINGS_FILE`은 이제 저장 폴더 해석에도 쓰인다.

단위 테스트(`StorageFolderCheckTests` 7개, `StorageFolderModelTests`·`StorageRootResolutionTests` 14개)로 확인함. 수동 확인이 남음(실제 앱): 폴더 선택 대화상자, 선택 취소 안내, 빈 설정 파일에서 첫 실행 모달(기본 폴더/폴더 선택/취소 시 모달 유지), 폴더 변경 후 Library와 새 저장이 새 폴더를 쓰는지, 쓸 수 없는 폴더의 안내.

## 5단계 권한 상태 기록 (STA-54)

설정 화면에 손쉬운 사용·클립보드·자동화 세 항목의 상태(허용/권한 필요/알 수 없음), 설명, 다음 행동을 보여 준다. 손쉬운 사용이 없으면 `시스템 설정 열기` 버튼이 시스템 설정의 손쉬운 사용 화면으로 이동한다. 자동화는 항상 `알 수 없음`이고 Chrome URL을 처음 읽을 때 macOS가 묻는다는 안내(`permissionAutomationNote`)를 붙인다. 앱이 다시 활성화될 때(`didBecomeActive`) 상태를 다시 읽는다.

단위 테스트(`PermissionsModelTests`, 8개)로 확인함: 손쉬운 사용·클립보드 판정(A-01, A-02), 자동화 항상 알 수 없음(A-03), 항목×상태 문구 키와 두 언어 존재(N-04), 시스템 설정 버튼은 손쉬운 사용이 없을 때만, 갱신 시 변경 반영.

수동 확인이 남음(실제 앱): A-01~A-04 모두. 손쉬운 사용을 켜고 끈 뒤 앱으로 돌아오면 화면이 갱신되는지, 버튼이 시스템 설정 손쉬운 사용 화면을 여는지, 권한이 없어도 앱이 종료되지 않는지. 클립보드는 `NSPasteboard`에 권한 조회 API가 없어 텍스트를 실제로 읽을 수 있으면 허용, 텍스트가 있는데 읽지 못하면 권한 필요, 비었거나 텍스트가 아니면 알 수 없음으로 표시한다(A-02). 설정 화면을 열 때와 앱이 활성화될 때 다시 읽는다.


## 5단계 단축키 변경 기록 (STA-55)

설정 화면의 `선택 텍스트 단축키` 섹션에서 바꾼다. 순서는 새 단축키 등록 → 이전 해제 → 설정 저장이며(`ShortcutController`), 등록 실패나 저장 실패면 이전 단축키가 계속 동작하고 설정 파일은 바뀌지 않는다. 저장 실패 뒤 이전 단축키를 다시 등록하지 못하면 `shortcut_rollback_failed`로 알린다. 거절된 입력은 필드에 남지 않고 동작 중인 단축키로 되돌아간다. 시작 시에는 저장된 단축키 하나만 등록하고, 실패하면 오류를 보관하고 메뉴 막대에 `Error`를 보인다(C-09). 새 오류 문구는 한국어·영어로 `shortcutRegistrationFailed`, `shortcutRollbackFailed`를 추가했고, 형식 오류는 `shortcutFormatHint`를 보인다. Carbon 핫키는 등록마다 고유 id를 붙여 교체 중 두 핫키가 동시에 살아 있어도 누른 쪽만 동작한다.

수동 확인이 남음(실제 앱): 단축키 변경 직후 새 단축키로 캡처되고 이전 것은 반응하지 않는지, 다른 앱이 쓰는 조합으로 바꾸면 한국어 오류가 나오고 이전 단축키가 계속 되는지, 재실행 후 유지되는지, F21–F24 입력 시 형식 안내가 나오는지.

## 5단계 이미지와 mixed 저장 기록 (STA-57)

`Save Clipboard...`로 이미지만 있는 클립보드는 `image` Draft, 텍스트와 이미지가 함께 있으면 `mixed` Draft가 된다. Save Popup은 이미지 미리보기를 보여 주고, `mixed`는 텍스트/이미지 분할 선택(기본 텍스트)을 주며 고른 유형 하나만 저장한다(D-02). 이미지는 `DropStore.saveImage`로 `image.png`에 저장하고, 비었거나 PNG가 아닌 이미지는 저장하지 않고 이유를 보여 준다(S-10). 캡처 단계에서도 PNG 시그니처가 아니면 `clipboard_image_unavailable`로 취급해 텍스트가 있으면 경고와 함께 텍스트로 진행한다. 임시 오류 코드 `clipboard_image_unsupported`와 문구 `clipboardImageUnsupported`는 제거했다.

단위 테스트로 확인함: 분류와 제목(`ClipboardCaptureTests`), 비PNG 바이트 거부, 팝업의 유형 선택과 저장 요청(`SavePopupImageTests`).

수동 확인이 남음(실제 앱): K-04(스크린샷 PNG와 TIFF를 내는 앱에서 저장), 이미지만/텍스트+이미지 클립보드에서 팝업 미리보기와 선택, 저장한 이미지 Drop이 Library 본문에 보임, P-09(선택 텍스트 캡처 전후로 이미지만/텍스트만/둘 다 있던 클립보드 복원). 폴백 복원은 TIFF만 있던 클립보드를 PNG로 되돌린다.

## 5단계 instant 모드 기록 (STA-58)

저장 확인 방식(`captureConfirmationMode`)이 캡처 동작에 연결됐다. 단축키와 `Save Clipboard...` 모두 같은 경로(`CaptureRouter`)를 지나며, 모드는 캡처마다 설정 파일에서 읽어서 재시작 없이 반영된다(읽을 수 없으면 팝업). `instant`에서 텍스트 Draft는 팝업 없이 노트 `""`·태그 없음으로 저장되고, 메뉴 막대에 `Saved`가 900 ms 보이고, Library가 새로고침되며 새 Drop이 선택된다. 이미지와 `mixed`는 `instant`에서도 팝업이다. 즉시 저장이 실패하면 오류를 보관하고(메인 창을 띄우지 않음) `Error`를 보인다. 즉시 저장은 태그가 없으므로 `recentTags`를 갱신하지 않는다.

단위 테스트로 확인함: 모드×유형 결정(`CaptureConfirmationTests`), 즉시 저장 요청 모양·팝업 경로·모드 재읽기·실패 보고(`CaptureRouterTests`), `Saved`/`Error` 900 ms와 교체(`MenuBarTests`).

수동 확인이 남음(실제 앱): `instant`로 바꾼 뒤 텍스트 선택 캡처(`Shift+Cmd+C`)와 `클립보드 저장...`이 팝업 없이 저장되고 `Saved`가 보이며 Library에 새 Drop이 선택됨, 이미지·mixed는 `instant`에서도 팝업, `modal`로 되돌리면 다시 팝업, 저장 폴더를 쓸 수 없을 때 `Error`가 보이고 다음에 메인 창을 열면 오류가 한 번 나옴.

## 5단계 수동 확인 기록 (STA-61)

2026-10-08에 사용자가 실제 앱(ad-hoc 서명 디버그 빌드)에서 직접 확인했고 문제가 없다고 보고했다. 다음 항목을 ☑로 바꿨다.

- 선택 텍스트 캡처: P-01(메모, Safari에서 출처와 선택 텍스트가 같은 앱), P-09(이미지만, 텍스트만, 둘 다 있던 클립보드가 캡처 뒤 그대로 복원), P-12(`instant`에서도 이미지·mixed는 팝업).
- 클립보드 캡처: K-04(스크린샷 PNG와 TIFF 이미지 저장), K-06(실패 시 `Error`만 표시하고 메인 창은 뜨지 않음).
- 설정: C-08(단축키 변경과 충돌 시 이전 단축키 유지), C-09(시작 시 저장된 단축키 하나만 등록), C-10(테마 즉시 적용과 `system` 복귀).
- 권한: A-01~A-04.
- 메뉴 막대: T-01, T-02, T-03(`Saved`와 `Error` 900 ms).

확인하지 않은 항목(P-02, P-13, P-15, M-03, M-04, T-04, I-05, D 항목)은 ☐로 남겼다.

## 단위 테스트 근거로 닫은 항목 (STA-61)

단위 항목은 같은 내용을 확인하는 Swift 테스트가 통과해 ☑로 바꿨다.

- P-03: `acceptsCopiedTextEqualToThePreviousClipboard`
- P-04: `timesOutAfterTwentyEightPollsAndRestores`, `blankClipboardAfterCopyIsNoSelectedTextAndRestores`, `readFailureAfterCopyRestoresAndReportsClipboardUnavailable`, `copyFailureRestoresTheClipboard`, `unchangedClipboardIsNotRewrittenWhenNothingWasCopied`
- P-05: `restoreFailureIsAWarningNotAFailure`
- P-06: `backupFailureWarnsContinuesAndStillAttemptsRestore`
- N-01: `LocalizationTests.koreanSystemLanguagesGetKoreanAndEverythingElseEnglish`
- N-02: `LocalizationTests.everyPhraseHasBothLanguagesWithTheSamePlaceholders`. 표가 키마다 en·ko를 함께 가지므로 한쪽에만 있는 문구는 만들 수 없고, 테스트는 두 언어가 채워져 있고 자리표시자가 같은지 확인한다.
- N-03: `LocalizationTests`의 알려진 코드 15개(코드별로 기대하는 문구 키까지 확인)와 알 수 없는 코드. **레거시와 다르게 정한 두 가지**: (1) 알 수 없는 코드의 오류는 레거시처럼 원본 메시지를 보여 주지 않고 기본 문구(`defaultError`)를 보여 준다. Swift의 `NotedropError.detail`은 사람용 문장이 아니라 로그용 원문(파일 경로, OS 영어 문구)이라 그대로 보여 주면 한국어 UI에 섞이고 경로가 노출된다. (2) "문자열 오류는 그대로"는 Swift에 문자열 오류 타입이 없어 해당 없음이고, `NotedropError`가 아닌 오류는 기본 문구로 가린다. 이 확인 중 `clipboard_restore_failed`, `automation_*` 문구를 추가했고 `empty_image`를 레거시처럼 `invalidImage`로 맞췄다.

P-02는 실제 대기 시간을 보는 수동 항목이라 ☐로 남긴다.

## Library 조작 수동 확인 기록 (STA-62)

2026-10-08 사용자가 실제 앱에서 확인했다. L-11, L-12, L-13, L-14를 ☑로 바꿨다.

- 처음 확인에서 우클릭 메뉴에 `Markdown 내보내기`와 구분선이 없고 `내용 복사`가 휴지통 뒤에 있었다. L-11 순서(출처 열기, 내용 복사, Markdown 내보내기, 구분선, 휴지통)로 고쳤다. 내보내기 로직은 상세 화면 버튼과 메뉴가 `LibraryModel.exportWithPanel`을 함께 쓴다.
- `Cmd+Backspace`는 처음에 아무 반응이 없었다. 목록 뷰의 키 핸들러(`onKeyPress`)로는 `Cmd` 조합이 도달하지 않아서, 목록에 포커스가 있을 때만 활성화되는 메뉴 명령 `휴지통으로 이동`(⌘⌫, `TrashCommand`)으로 바꿔 동작을 확인했다. 노트·태그 입력창에서는 메뉴 항목이 비활성이라 글자 지우기가 그대로 동작한다.
- 출처 열기(URL 없을 때 비활성)와 Markdown 내보내기 취소(파일 미생성)는 이상 없음.
