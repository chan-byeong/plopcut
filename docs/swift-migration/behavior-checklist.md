# 동작 체크리스트

Linear: STA-39 · 사양: [spec.md](spec.md) · 픽스처: [fixtures/](fixtures/README.md)

레거시 코드와 PRD에만 남아 있고 화면만 봐서는 놓치기 쉬운 동작을 모았습니다. 구현이 끝나면 항목마다 "확인 방법"을 수행해
체크하세요. **근거**는 레거시(`legacy/tauri` 브랜치) 파일입니다. 그 파일을 읽어야 한다는 뜻이 아니라, 동작에 의문이 생겼을 때
찾아볼 위치입니다. 함수 이름이 `테스트:`로 시작하면 레거시 테스트가 그 동작을 고정하고 있으므로 같은 시나리오를 Swift 테스트로
옮기면 됩니다.

체크 표시 ☑는 구현과 자동 테스트로 확인한 항목입니다(STA-41, `PlopcutCore`). 일부만 확인한 항목은 ☐로 두고 아래에 이유를 적습니다.

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
| S-21 | `drop.json`에 `pinnedAt`(시각 문자열 \| null)을 항상 쓴다. 키가 없는 예전 `drop.json`은 고정 안 됨으로 읽는다(PLO-102). | spec 1.2 | 단위·픽스처: `image-drop`(고정), `legacy-minimal-text`(키 없음) | ☑ |
| S-22 | 고정·고정 해제는 `pinnedAt`만 바꾸고 `updatedAt`과 다른 파일은 그대로 둔다. 이미 고정한 Drop을 다시 고정하면 처음 시각을 유지한다. | spec 1.2 | 단위 | ☑ |
| S-23 | 텍스트·이미지 Drop을 처음부터 고정한 상태로 저장할 수 있다(`pinnedAt` = `createdAt`). | spec 1.2 | 단위 | ☑ |

## C. 설정

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| C-01 | 설정 파일 경로는 고정(`~/Library/Application Support/plopcut/settings.json`)이고 저장 폴더 설정과 무관. | `settings.rs` | 단위 | ☑ |
| C-02 | 파일이 없으면 기본값을 만들어 저장. JSON이 깨지면 `settings_invalid`. | 테스트: `default_settings_use_default_storage_and_system_theme` | 단위·픽스처 | ☑ |
| C-03 | 부분 갱신: 보낸 필드만 바꾸고 나머지는 유지, `updatedAt` 갱신. | 테스트: `updating_settings_persists_path_first_run_theme_and_updated_at`, `updating_settings_persists_shortcuts_without_changing_unrelated_fields` | 단위 | ☑ |
| C-04 | `captureConfirmationMode` 키가 없으면 `modal`. 잘못된 값으로 갱신하면 거부. | 테스트: `missing_capture_confirmation_mode_defaults_to_modal`, `update_rejects_invalid_capture_confirmation_mode`, `changingCaptureModePersistsAndKeepsTheme` | 단위 | ☑ |
| C-05 | `paneWidths`는 읽고 쓸 때 180–320 / 300–560으로 고정, `recentTags`는 태그 규칙과 12개 제한. | 테스트: `updating_settings_persists_pane_widths_and_recent_tags` | 단위 | ☑ |
| C-06 | 단축키 문자열은 Tauri 문법(`Shift+Cmd+K`)으로 저장. Swift가 이 문자열을 파싱해야 하며 파싱 불가면 저장 거부. 파일은 바뀌지 않아야 한다. Swift 설정 화면은 문자열 입력 대신 키 녹화로 받는다(STA-69): 입력란을 누르고 키 조합을 누르면 같은 문법의 문자열(`Ctrl+Option+Shift+Cmd+키` 순서)이 되고, 수식 키만 누르면 확정하지 않으며, 수식 키가 없거나 D-03 범위 밖의 키는 이유를 보이고 거부하고, Esc만 누르면 녹화를 취소한다. | 테스트: `update_rejects_unparseable_selected_text_shortcut`, `update_rejecting_invalid_shortcut_leaves_persisted_settings_file_untouched` | 단위(앱): `ShortcutRecordingTests`(허용 키 전체, 수식 키 순서, 수식 키가 아닌 플래그 무시, 수식 키만은 미리보기만, 수식 키 없음·범위 밖 거부, Esc 취소, 기록한 문자열이 누른 키로 등록됨), `ShortcutModelTests`(거부 이유 표시와 녹화 유지, 거절된 단축키가 필드에 남지 않음). 단위: 수식어(`Shift`, `Cmd`/`Command`, `Ctrl`/`Control`, `Alt`/`Option`)와 키 이름. 수동(STA-69): 실제 키 녹화 | ☐ |
| C-07 | 원자적 쓰기(임시 파일 + 이름 변경)로 쓰고 쓰기 실패 시 임시 파일을 지운다. 동시 갱신은 직렬화. | `atomic_write_settings`, `SETTINGS_UPDATE_LOCK` | 단위 | ☑ |
| C-08 | 단축키 변경 순서: 새 것 등록 → 이전 것 해제 → 설정 저장. 어느 단계가 실패해도 이전 단축키가 살아 있어야 한다. 이 순서는 설정 화면의 `저장` 버튼을 누를 때 한 번에 실행한다. 녹화·선택 중에는 실제 단축키와 설정 파일이 바뀌지 않고, `취소`나 설정 화면을 떠나면 고른 조합을 버리고 이전 단축키를 유지한다(STA-70). | 테스트: `changing_selected_text_shortcut_replaces_the_old_registration`, `failed_registration_keeps_the_previous_shortcut_active`, `persistence_failure_restores_the_previous_shortcut` | 단위(가짜 등록기): `ShortcutControllerTests` (등록→해제→저장 순서, 등록 실패·저장 실패 롤백, 롤백 실패 `shortcut_rollback_failed`), `ShortcutModelTests`(실제 `ShortcutController`와 가짜 등록기로 저장 전에는 등록·저장 호출 없음, 저장 때 등록→해제→저장, 녹화 취소·버리기 후 변화 없음) + 수동(실제 충돌, STA-70 저장 전 미적용) | ☐ |
| C-09 | 시작 시 저장된 단축키 하나만 등록(다른 단축키는 등록하지 않음). 등록 실패는 보관 오류와 메뉴 막대 실패 표시(T-03)로 알린다. | 테스트: `startup_registers_only_the_selected_text_shortcut` | 단위: `ShortcutControllerTests.startupRegistersOnlyTheStoredShortcut` + 수동 | ☑ |
| C-10 | `theme`가 `system`이면 앱 외형을 시스템에 맡기고, `light`/`dark`는 시스템을 덮어쓴다. 저장된 테마는 앱 시작 시 첫 창부터 적용된다(PLO-95: `App.init`에는 아직 `NSApp`이 없어 `willFinishLaunching`에서 적용). | `useTheme.ts`. Swift: `SettingsModel.colorScheme`, 테스트 `colorSchemeFollowsTheme`, `changingThemePersistsAndKeepsOtherFields`, `aStoredThemeIsAppliedWhenTheAppFinishesLaunching` | 단위(모델) + 수동(창 외형) | ☑ |
| C-11 | 읽은 `theme`이 잘못되면 `system`으로 보정, `storageFolderPath`가 공백이면 기본 폴더. | `read_app_settings_from_path` | 단위 | ☑ |
| C-12 | 번들 ID를 바꾸면 손쉬운 사용·자동화 권한을 새로 허용해야 한다. 설정과 Drop은 영향이 없다. `app.notedrop.dev` → `com.plopcut.app`(STA-85). | — | 수동 | ☑ |
| C-13 | 시작 시 예전 `Notedrop` 설정·기본 Drop 폴더·로그 폴더를 `plopcut`으로 옮기고 `storageFolderPath`를 새 경로로 저장한다(사양 1.9). | `LegacyMigration` | 단위: `movesSettingsAndTheDefaultDropFolder`, `movesTheLogFolderAndRenamesItsFiles` + 수동: 예전 폴더 복사본 | ☐ |
| C-14 | 사용자 지정 저장 폴더는 옮기지 않는다. | `LegacyMigration` | 단위: `keepsACustomStorageFolder` | ☑ |
| C-15 | `plopcut` 폴더가 이미 있으면 덮어쓰거나 합치지 않는다. 예전 폴더가 없으면 아무것도 하지 않는다. 설정 저장 실패는 폴더 이동을 되돌리고, 읽을 수 없는 설정이면 옮기지 않는다. | `LegacyMigration` | 단위: `neverOverwritesExistingPlopcutFolders`, `doesNothingWithoutLegacyFolders`, `rollsTheDropFolderBackWhenSettingsCannotBeSaved`, `aBrokenSettingsFileLeavesTheDropFolderAlone` | ☑ |

## P. 캡처 (선택 텍스트)

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| P-01 | 출처 수집이 선택 텍스트 읽기(접근성·클립보드 폴백 모두)보다 **먼저**. 앞 앱은 캡처 시작 때 한 번만 정하고 출처 수집과 선택 읽기가 같은 앱을 쓴다(STA-50). | 테스트: `selected_text_capture_collects_source_first_and_restores_text_and_image`, `frontmostAppIsResolvedOnceAndSharedByCollectorAndReader` | 단위(호출 순서) | ☑ |
| P-02 | **(폴백 경로)** 복사 후 대기: 변경 횟수가 달라질 때까지 25 ms 폴링, 최대 700 ms. | `SELECTED_TEXT_COPY_TIMEOUT`, `POLL_INTERVAL` | 단위·수동 | ☑ |
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
| P-13 | 선택 텍스트 캡처 실패: 오류 보관 + 메뉴 막대 실패 표시(T-03)만, 메인 창은 열지 않는다(PLO-96). 예외로 `permission_missing`은 메인 창을 열어 이유와 `시스템 설정 열기`를 보인다. 보관 오류는 메인 창에서 **한 번만** 소비. | `CaptureRuntime.report`, 테스트: `pending_capture_error_is_returned_once` | 단위·수동 | ☐ |
| P-14 | 별도 팝업 창이 이미 열려 있으면 단축키는 새 캡처를 하지 않고 열린 팝업을 앞으로 가져온다(결정 STA-47). 팝업이 열려 있으면 키보드가 팝업에 있어 선택 텍스트 캡처가 팝업 자신을 읽기 때문이다(PLO-96부터 팝업은 앱을 활성화하지 않지만 키보드는 가져간다). 레거시의 "새 Draft로 교체"와 다르다. | `open_capture_window` | 수동: 팝업을 연 채 단축키 재입력 | ☑ |
| P-15 | 레거시는 클립보드 접근을 `swift -e` 서브프로세스로 했다. Swift 앱은 `NSPasteboard`를 직접 쓰므로 이 구조는 이어받지 않는다(같은 시맨틱만 유지). | `capture.rs` | — | ☑ |
| P-16 | 접근성 읽기(`AXUIElementCreateApplication(최전면 앱)` → 포커스 요소 → `AXSelectedText`)가 비어 있지 않은 값을 주면 클립보드를 읽거나 쓰지 않고, `Cmd+C`도 보내지 않는다. 시스템 전역 요소는 쓰지 않는다(Chrome에서 실패). | [ax-probe.md](ax-probe.md) | 단위(가짜 호출 기록) + 수동: 메모·Chrome에서 캡처 전후 클립보드 `changeCount` 동일 | ☑ |
| P-17 | 접근성 읽기가 실패하거나 값이 비거나 공백뿐이면 클립보드 폴백(P-02~P-09)으로 넘어가며, 그 자체로 `no_selected_text`로 보지 않는다. 최전면 앱이 plopcut이면 접근성 읽기를 건너뛴다. | [ax-probe.md](ax-probe.md) | 단위 + 수동: Safari·터미널(Hyper)에서 폴백으로 저장 | ☑ |

## K. 클립보드 캡처 (메뉴 막대 `Save Clipboard`)

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| K-01 | 변경 횟수를 읽기 전후로 비교해 다르면 `clipboard_changed`. | 테스트: `ClipboardCaptureTests.rejectsContentChangedDuringRead`, `acceptsAnUnchangedCountAndAnUnreportedCount` | 단위 | ☑ |
| K-02 | 분류: 텍스트만 `text`, 이미지만 `image`, 둘 다 `mixed`, 둘 다 없으면 `clipboard_empty`. | 테스트: `textOnlyBecomesATextDraft`, `mixedContentKeepsBothForThePopupToChooseFrom`, `imageOnlyBecomesAnImageDraft`, `imageFromPlopcutHasNoSourceAndTheFallbackTitle`, `emptyOrBlankClipboardFailsAsEmpty`; 팝업에서 고른 유형만 저장: `SavePopupImageTests` | 단위 | ☑ |
| K-03 | 이미지 디코딩 실패 시 텍스트가 있으면 텍스트로 진행하고 경고 `clipboard_image_unavailable`. 텍스트도 없으면 그 오류로 실패. | 테스트: `undecodableImageFallsBackToTextWithAWarning`, `undecodableImageWithoutTextFails`, `readFailureIsReportedAsUnavailable` | 단위 | ☑ |
| K-04 | 이미지는 PNG가 있으면 PNG, 없으면 TIFF를 PNG로 변환해 사용. | `read_clipboard_snapshot` | 수동: 스크린샷(PNG)과 TIFF를 내는 앱 | ☑ |
| K-05 | 최전면 앱이 plopcut이면 출처를 비우고 제목을 다시 추론. 다른 앱이면 출처 유지. | 테스트: `omitsPlopcutAsSourceAndReinfersTheTitle`, `keepsTheSourceOfAnotherApp` | 단위 | ☑ |
| K-06 | 클립보드 캡처 실패는 오류 보관 + 메뉴 막대 실패 표시(T-03)만(메인 창을 띄우지 않음). | `CaptureRuntime.reportQuietly`(Error만 표시하고 오류를 보관, 메인 창은 띄우지 않음) | 수동 | ☑ |

## M. 출처 수집

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| M-01 | 최전면 앱 이름과 앞 윈도우 제목. 제목을 못 얻어도 앱 이름은 유지. | `collect_source_metadata` | 수동 | ☑ |
| M-02 | 앱이 `Google Chrome`일 때만 활성 탭 URL을 시도. 실패는 경고 `chrome_url_failed`, 앱·윈도우 실패는 `metadata_failed`. | 위와 같음 | 수동: 권한 거부 상태 | ☑ |
| M-03 | 출처 수집 실패는 저장을 막지 않는다. 비어 있는 필드는 `null`로 저장. | PRD "Source metadata" | 단위 | ☑ |
| M-04 | 파일 경로는 레거시가 수집하지 않는다. 신뢰할 수 있는 API가 없으면 비워 둔다. | `collect_source_metadata` | — | ☑ |

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
| L-01 | 검색은 제목·본문·노트·이미지 경로·앱·윈도우·URL·태그의 부분 문자열(대소문자 무시). 이미지 경로(`image.png`)로도 검색된다. 질의와 필드는 소문자화 후 NFC로 맞춰 분해형(NFD)·완성형 한글이 서로 찾힌다(STA-82). | `drop-utils.ts` `matchesDropSearch` | 단위 | ☑ |
| L-02 | 기간 필터: 오늘은 같은 달력 날짜, 7·30일은 `createdAt ≥ 지금 − N일`. 날짜를 해석할 수 없는 Drop은 기간 필터에서 제외. | `matchesDateFilter` | 단위 | ☑ |
| L-03 | 날짜 그룹: 오늘/어제/지난 7일(2~7일 전)/이전. 해석 불가한 날짜는 `이전`. 빈 그룹 숨김. | `drop-groups.ts` | 단위 | ☑ |
| L-04 | 선택이 필터 결과에서 사라지면 첫 항목, 결과가 비면 선택 없음. | `useLibraryFilters.ts` | 단위 | ☑ |
| L-05 | 사이드바 선택은 항상 하나. 유형 선택은 태그 필터를 지우고 태그 선택은 유형을 `all`로 돌린다. 필터 지우기는 출처·기간만 지운다(PLO-103에서 앱 → 출처). | `Sidebar.tsx`, `useLibraryFilters.ts`(STA-37) | 단위 | ☑ |
| L-06 | 사이드바 접힘은 Library↔Settings 전환과 창 크기 변경을 지나도 유지. 두 화면에서 사이드바 너비·모양이 같다. | `MainWindow.tsx`(STA-38) | 수동 | ☑ |
| L-07 | 인스펙터 오버레이: 같은 토글 또는 Escape로 닫고 Drop 목록으로 포커스 복귀(D-13). 검색 편집 중 Escape는 검색을 먼저 닫는다. | STA-30 검증 기록(저장소에 미포함) | 수동 | ☑ |
| L-08 | 검색을 닫아도(Escape) 검색어와 결과 유지. 지우기는 전체 복원. `Cmd+F`는 검색 포커스. | `design-system.md` | 수동 | ☑ |
| L-09 | 새로고침은 디스크를 다시 스캔한다. 다른 곳(팝업 창 등)의 저장 신호를 받아도 다시 스캔한다. | `useLibraryRefreshEvent.ts` | 수동 | ☑ |
| L-10 | Save Popup에서 저장하면 Library가 새로고침되고 새 Drop이 선택된다. | `handleCaptureSaved` | 단위(`LibraryModel`) + 수동 | ☑ |
| L-11 | 목록 우클릭 메뉴: 출처 열기(URL 있을 때), 이 출처의 드롭 보기(PLO-103, L-20), 내용 복사(텍스트일 때), Markdown 내보내기, 구분선, 휴지통. 우클릭하면 그 행을 먼저 선택. | `LibraryPane.tsx` | 수동 | ☑ |
| L-12 | `Cmd+Backspace`는 삭제 확인 시트, 확인 후에만 휴지통으로 이동. | `LibraryPane.tsx`, `DeleteConfirmationSheet.tsx` | 수동 | ☑ |
| L-13 | 출처 열기: URL이 비어 있으면 `source_url_missing`. 버튼은 URL이 없을 때 비활성. | `commands.rs` `open_source_url` | 단위·수동 | ☑ |
| L-14 | Markdown 내보내기: 취소하면 파일을 쓰지 않는다. 형식은 spec 7장. | `markdown.rs`, 테스트: `markdown_generation_includes_drop_fields` | 단위 | ☑ |
| L-15 | 창 크기 때문에 줄어든 표시 너비를 `paneWidths`에 저장하지 않는다. 구분선 조절이 끝났을 때만 저장. | `MainWindow.tsx` | 수동 | ☑ |
| L-16 | 출처 키: http(s) URL의 호스트를 소문자로, 앞의 `www.` 하나만 떼고 하위 도메인은 유지. http가 아닌 URL과 URL 없는 Drop은 앱 이름, 둘 다 없으면 출처 없음. | 스펙 1.6(PLO-103) | 단위(`SourceKeyTests`) | ☑ |
| L-17 | 출처 필터: 고른 출처끼리 OR, 검색·Collection·기간과 AND. 출처 필터가 걸리면 출처 없는 Drop은 빠지고, 걸리지 않으면 보인다. 앱 필터는 없다. | 스펙 1.6, 2.5(PLO-103) | 단위(`LibraryTests`) | ☑ |
| L-18 | 필터 팝오버: 출처 검색, 웹사이트·앱 묶음, 출처마다 체크박스와 개수(출처 필터를 뺀 조건 기준), 여러 개 선택, 기간 분할 컨트롤(전체/오늘/7일/30일). 문구 끝에 말줄임 없음. | 스펙 2.5(PLO-103) | 단위(`LibraryModelTests`) + 수동 | ☐ |
| L-19 | 고른 출처마다 `출처: {source}` 칩 하나. 칩을 누르면 그 출처만 해제. 필터 지우기는 사이드바 선택을 유지. | 스펙 2.5(PLO-103) | 단위(`LibraryModelTests`) + 수동 | ☐ |
| L-20 | `이 출처의 드롭 보기`(인스펙터 출처 칸, 우클릭 메뉴): Collection을 라이브러리로, 출처 필터를 그 출처 하나로. 기간은 유지. 출처 없는 Drop에서는 비활성. | 스펙 2.5, 2.7(PLO-103) | 단위(`LibraryModelTests`) + 수동 | ☐ |
| L-21 | 목록 맨 위 `고정됨` 묶음: 현재 검색·Collection·필터 결과 안의 고정한 Drop만, `pinnedAt` 최근순(같으면 `id` 내림차순). 날짜 그룹에 다시 나오지 않는다(PLO-102). | spec 1.6 | 단위(`LibraryTests`) | ☑ |
| L-22 | 사이드바 보관함의 `고정됨` Collection: 개수는 고정한 Drop 수, 고르면 태그 필터를 지우고 유형은 전체. 묶음 제목 없이 고정 시각순. | spec 2.4, 2.5 | 단위(`LibraryModelTests`) + 수동 | ☐ |
| L-23 | 동작 버튼, 우클릭 메뉴 맨 위 항목, `Shift+Cmd+P`로 고정·고정 해제. 고정한 Drop에서는 문구가 `고정 해제`이고 동작 버튼이 눌린 상태. 고정 후 선택 유지. | spec 2.5, 2.6 | 단위(`LibraryModelTests`) + 수동 | ☐ |
| L-24 | 고정한 행에 파란 핀 아이콘, VoiceOver는 `고정됨`을 읽는다. | spec 2.5 | 단위(접근성 라벨) + 수동(VoiceOver) | ☐ |
| L-25 | 동작 버튼은 아이콘만 있는 38×26 pt, 순서 고정 · 출처 열기 · Markdown 내보내기 \| 휴지통(빨강, 구분선 뒤). 툴팁 `이름 (단축키)`, 버튼마다 접근성 이름. 더 보기 버튼 없음. 우클릭 메뉴 항목에 단축키 표시. | spec 2.6 | 단위(툴팁 문구) + 수동(시안 MainFeatures, FeatureDetails 3번) | ☐ |

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
| I-04 | 팝업 `Cmd+Enter` 저장(저장 중이면 무시), Escape 취소. 레거시는 `Cmd+Enter`에서 입력기 조합 여부를 검사하지 않는다(조합 중에도 동작). 웹 textarea처럼 조합 중인 글자도 노트 값에 들어 있으므로 Swift 노트도 화면에 보이는 글자(조합 중 글자 포함)를 저장한다(STA-66). | `SavePopover.tsx`, 단위: `SavePopupWindowTests.NoteEditor.savingClosesAnOpenCompositionAndKeepsItsCharacters` | 수동 | ☑ |
| I-05 | 포커스 링은 컨트롤 모양을 따르는 둥근 링이고 레이아웃을 밀지 않는다. 컨테이너에는 링이 없다. 목록 행은 안쪽 링. | STA-38 CSS(실제 앱 미검증) | 수동 | ☑ |
| I-06 | 제목 인라인 이름 변경: Return 확정, Escape 되돌림, 둘 다 포커스를 목록에 돌린다. | STA-38(실제 앱 미검증) | 수동 | ☑ |
| I-07 | Save Popup 맨 위 제목 입력란에 저장할 유형의 자동 제목(윈도우 제목 → 앱 이름 → 본문 첫 줄 → 기본 제목)을 미리 채운다. 입력란을 건드리지 않고 저장하면 PLO-105 이전과 같은 제목이다. | 스펙 1.4, 3.5(PLO-105) | 단위(`SavePopupModelTests`) + 수동 | ☐ |
| I-08 | 고치기 전에는 `mixed` Draft의 유형을 바꾸면 제목이 그 유형의 자동 제목으로 바뀌고, 고친 뒤에는 그대로다. `자동` 버튼은 입력값이 자동 제목과 다를 때만 활성이고 누르면 자동 제목으로 되돌린다. | 스펙 3.5(PLO-105) | 단위(`SavePopupModelTests`) + 수동 | ☐ |
| I-09 | 입력란을 비우고(공백뿐 포함) 저장하면 명시한 제목 없이 보내 저장소가 자동 제목을 쓴다. 그 밖에는 앞뒤 공백을 지운 값을 명시한 제목으로 저장한다(80자 제한). 입력란 아래 문구가 자동 제목의 출처(윈도우 제목/앱 이름/본문 첫 줄/없음)와 비우면 자동 제목을 쓴다는 점을 알리고, 끝에 말줄임이 없다. | 스펙 1.4, 3.5(PLO-105) | 단위(`SavePopupModelTests`, `LocalizationTests`) + 수동 | ☐ |
| I-10 | 제목 입력란에 포커스가 있어도 `Cmd+Enter`는 저장, Escape는 취소다. | 스펙 3.5(PLO-105) | 단위(`SavePopupWindowTests`) + 수동 | ☐ |
| I-11 | `저장 후 고정` 체크박스: 기본 꺼짐, 팝업을 열 때마다 꺼짐. 켜고 저장하면 고정한 상태로 저장되어 Library `고정됨` 묶음에 나타난다. | 스펙 3.5(PLO-105) | 단위(`SavePopupModelTests`) + 수동 | ☐ |
| I-12 | 제목 입력란과 체크박스가 들어가도 Save Popup이 내용을 자르지 않는다. 경고·태그가 없는 Draft의 최소 높이는 스펙 2.1의 값이다. | 스펙 2.1, 3.5(PLO-105) | 단위(`SavePopupWindowTests.Layout`) + 수동(시안 SavePopupTitle) | ☐ |

## T. 메뉴 막대

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| T-01 | 템플릿 아이콘, 툴팁 `plopcut`. 좌클릭과 우클릭 모두 같은 메뉴를 열고, 메뉴를 열어도 앱이 활성화되거나 메인 창이 앞으로 오지 않는다(PLO-96에서 변경, 이전에는 좌클릭이 메인 창 열기). 메인 창은 메뉴의 `Open Library`로 연다. 아이콘은 "p." 마크의 단색 템플릿 이미지([구현 명세 5.1](spec.md#51-브랜드-마크와-앱-아이콘), PLO-89에서 변경, PLO-90에서 구현). | `MenuBarController`(`NSMenuDelegate`), PLO-89, PLO-96 | 수동 | ☐ |
| T-02 | 메뉴 항목 ID는 `save-clipboard`, `open-library`. 알 수 없는 ID는 무시. | 테스트: `routes_stable_tray_menu_ids`, `save_clipboard_menu_action_starts_clipboard_capture` | 단위 | ☑ |
| T-03 | 제목 문구 없이 점 자리 기호로 알린다(스펙 2.1). 성공: 점이 떨어져 앉고(200 ms) 체크로 바뀐 뒤 약 1.1초 뒤 점으로 복원. 실패: 240 ms 흔들림 후 느낌표가 메뉴를 열 때까지 남고, 메뉴를 열면 점으로 복원. 실패 중 성공이 오면 성공 표시로 바뀐다. '동작 줄이기'에서는 움직임 없이 기호만 바뀐다. 접근성 이름·툴팁이 상태(`menuBarSaved`, `menuBarFailed`)를 알린다. 성공 표시는 팝업 저장과 instant 저장 모두에 나온다(PLO-98). (레거시와 PLO-89 이전 Swift는 `Saved`/`Error`를 900 ms 제목으로 표시했다.) | `show_feedback`, PLO-89 | 단위: 상태 전환과 시간(가짜 시계), 메뉴 열기 시 복원 + 수동: 동작 줄이기, VoiceOver | ☐ |
| T-04 | 메인 창을 열 때 보관된 캡처 오류를 확인하도록 신호를 보낸다. 캡처 실패 자체는 메인 창을 열지 않는다(`permission_missing` 제외, PLO-96). | `show_main_window` | 수동 | ☑ |
| T-05 | 실패 표시 중 메뉴 맨 위에 `저장 실패` 제목, 오류 사유(지역화 문구), 구분선, `설정 열기`가 있고, `설정 열기`는 메인 창의 Settings 화면을 연다. 실패 표시가 없으면 이 항목이 없다. | PLO-89 | 단위(메뉴 구성) + 수동 | ☐ |

## N. 지역화

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| N-01 | 시스템 언어가 `ko`로 시작하면 한국어, 아니면 영어. | `i18n.tsx` `resolveLocale` | 단위 | ☑ |
| N-02 | 두 언어의 키 집합이 같다(한쪽에만 있는 문구 없음). | `i18n.tsx` `Dictionary` 타입 | 단위 | ☑ |
| N-03 | 알려진 오류 코드는 지역화한 문구로, 그 밖에는 `defaultError`. (레거시는 그 밖의 코드를 원본 메시지로, 문자열 오류를 그대로 보여 줬다. Swift는 `detail`이 로그용이라 의도적으로 다르게 간다. 아래 STA-61 기록 참고.) | `translateError` | 단위 | ☑ |
| N-04 | 권한 상세 문구는 항목×상태(허용/없음)로 키가 있고, `알 수 없음`은 `permissionUnknownDetail`. | `permissionDetail` | 단위 | ☑ (`PermissionsModelTests.detailKeysFollowItemAndStatusAndUnknownIsShared`, `everyDetailAndStatusKeyHasBothLanguages`) |

## U. 브랜드와 UI v2 (PLO-89)

2026-10-15 소유자가 채택한 브랜드 마크와 UI v2입니다. 기준은 [스펙](spec.md) 2.3–2.5, 3.5, 4, 5장, [구현 명세 5.1](spec.md#51-브랜드-마크와-앱-아이콘),
[디자인 시스템](../design-system.md)입니다. 구현 이슈가 끝나면 체크합니다.

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| U-01 | 앱 아이콘이 그래파이트 `#26282C` 바탕에 흰 p와 `#4F8CFF` 점인 "p." 모노그램이다(그라데이션 없음). 메뉴 막대는 같은 마크의 템플릿 이미지다. | [구현 명세 5.1](spec.md#51-브랜드-마크와-앱-아이콘) | 수동: Finder·Dock·메뉴 막대(라이트·다크) | ☐ |
| U-02 | 앱 강조색이 라이트 `#2F6BFF`, 다크 `#4F8CFF`이고, 활성 창의 사이드바·목록 선택 행은 이 강조색에서 만든 시스템 선택색(흰 글자 대비 4.5:1 이상), 비활성 창은 중성색이다(PLO-91에서 직접 칠하지 않기로 함). 사이드바 아이콘과 목록 행 태그는 `.secondary` 회색이다. | 스펙 2.4, 5장 | 수동: 라이트·다크, '대비 증가' | ☐ |
| U-03 | Library 도구 막대가 [필터 · 필터 지우기(`xmark.circle`, 필터가 있을 때만)] [인스펙터 토글] [검색(macOS가 맨 오른쪽에 둠)]뿐이다(PLO-92). 새로고침은 메뉴 `Cmd+R`, 설정 전환 버튼은 없다. Settings 도구 막대는 제목만 있다. | 스펙 2.3 | 단위(메뉴 명령) + 수동 | ☐ |
| U-04 | 태그 아이콘이 `number`이고 목록 행, 인스펙터·팝업 칩, 최근 태그가 `#design`처럼 표시된다. 저장 값에는 `#`이 없다. | 스펙 1.5, 2.4, 2.5, 5장 | 단위(저장 값) + 수동 | ☐ |
| U-05 | 빈 Library에 컬러 마크, `noDropsTitle`, `noDropsShortcutHint`, 현재 단축키 키캡(기본 ⇧ ⌘ C), `noDropsClipboardHint`가 보이고 키캡 묶음이 단축키를 하나의 접근성 이름으로 읽는다. | 스펙 2.5 | 수동 + VoiceOver | ☐ |
| U-06 | Settings 정보 섹션에 앱 아이콘, `plopcut`, `aboutVersion`이 한 줄로 있다. Save Popup 제목 앞에 작은 마크, 출처 앞에 출처 앱 아이콘, 하단에 `popupShortcutHint`가 있다. | 스펙 3.5, 4장 | 수동(한국어·영어) | ☐ |

## R. 본문 렌더링과 형식 (PLO-101)

텍스트 Drop 본문의 형식 감지, Markdown·코드 렌더링, 형식 메뉴입니다. 기준은 [스펙](spec.md) 1.2, 2.6 "형식과 렌더링", 3.5입니다.

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| R-01 | `drop.json`에 `format`·`codeLanguage`를 항상 쓴다(없으면 `null`). 키가 없거나 `format`이 모르는 값이면 자동 감지로 읽고 경고를 내지 않는다. `format`이 `code`가 아니면 `codeLanguage`는 무시한다. | 스펙 1.2 | 단위 + 픽스처(`storage-format`) | ☑ |
| R-02 | 형식을 바꾸거나 지워도 `updatedAt`과 `content.md`는 그대로다. 제목·노트·태그·본문 수정은 여전히 `updatedAt`을 바꾼다. | 스펙 1.2 | 단위 | ☑ |
| R-03 | 자동 감지: Terminal·iTerm·Xcode 출처는 코드(Shell/Swift), 전체가 JSON 객체·배열이면 코드(JSON), Markdown 신호가 뚜렷하면 Markdown, 나머지와 `*`·`#`이 섞인 평문은 일반 텍스트. 사용자가 고른 형식이 감지보다 먼저다. | 스펙 2.6 | 단위(`FormatDetectionTests`) | ☑ |
| R-04 | Markdown의 제목, 문단, 굵게·기울임, 인라인 코드, 중첩 목록, 인용, 구분선, 링크, 코드 블록을 렌더링하고, 표·이미지·HTML은 원문 텍스트로 보여 준다. 이미지는 불러오지 않는다. | 스펙 2.6 | 단위(렌더 모델) + 수동 | ☐ |
| R-05 | 코드 블록에 언어 이름, `코드 복사` 버튼(코드만 복사), 문법 하이라이팅(라이트 `github`, 다크 `github-dark`)이 있고 두 외형 모두 읽을 수 있다. | 스펙 2.6 | 단위(복사·하이라이트 색) + 수동(라이트·다크) | ☐ |
| R-06 | 렌더링한 본문을 선택하고 복사할 수 있다. | 스펙 2.6 | 수동 | ☐ |
| R-07 | `http`·`https`·`mailto` 링크만 누를 수 있고 기본 브라우저(기존 URL 열기 경로)로 연다. 그 밖의 주소는 글자만 보인다. | 스펙 2.6 | 단위(렌더 모델, `LibraryModel.openLink`) + 수동 | ☐ |
| R-08 | 형식 메뉴: `자동 감지 (감지 결과)`, `일반 텍스트`, `Markdown`, `코드 ▸ 언어`. 고른 값은 앱을 다시 실행해도 유지되고, `자동 감지`를 고르면 선택이 지워진다. 형식을 바꿔도 선택한 Drop과 목록 위치는 유지된다. | 스펙 2.6 | 단위(`LibraryModel`) + 수동 | ☐ |
| R-09 | Save Popup 미리보기가 같은 방식으로 렌더링되고 형식 배지를 보여 준다. | 스펙 3.5 | 수동 | ☐ |
| R-10 | VoiceOver가 제목(역할·단계), 목록, 코드 블록(`코드 블록, 언어`)과 `코드 복사` 버튼 이름을 읽는다. | 스펙 2.6 | 수동(VoiceOver) | ☐ |

## D. 결정이 필요한 차이와 알려진 공백

레거시에서 확인되지 않았거나 문서와 구현이 어긋난 곳입니다. 구현 전에 결정하거나 확인해 기록하세요.

| ID | 상황 | 제안 | 결정 | ☐ |
| --- | --- | --- | --- | --- |
| D-01 | PRD는 `Shift+Cmd+V`(클립보드 캡처)를 요구하지만 구현된 적이 없다. 클립보드 캡처는 메뉴 막대의 `Save Clipboard`뿐이다. | 먼저 레거시와 같게 메뉴만 구현. 단축키는 별도 요청이 있을 때. | | ☑ |
| D-02 | 타입에 `mixed`가 있지만 **저장되는 Drop은 `text` 또는 `image`뿐**이다(`mixed` Draft는 팝업에서 하나를 고른다). 레거시는 `mixed` Drop을 목록에는 보여 주지만 본문과 이미지를 읽지 않는다(픽스처로 확인). | 최소한 레거시와 같게(깨지지 않고 목록에 표시). 본문·이미지 표시는 별도 결정. | | ☑ |
| D-03 | 레거시 단축키 문자열은 Tauri 문법이다. 전체 허용 범위(예: 방향키, 펑션키, `CmdOrCtrl`)는 문서화되어 있지 않다. | 최소 `Shift/Cmd/Ctrl/Alt` + 문자·숫자·펑션키를 지원하고 나머지는 거부. | | ☑ |
| D-04 | 이미지 Drop의 `image.png`가 아닌 다른 `imagePath`를 읽는 경로는 있으나(`drop.imagePath`) 쓰는 경로는 항상 `image.png`다. | 읽기는 `imagePath` 우선, 쓰기는 `image.png`. | | ☑ |
| D-05 | 도구 막대 `선택한 텍스트 캡처`는 plopcut이 최전면일 때 plopcut 안의 선택 텍스트만 캡처한다(다른 앱의 선택을 가져오지 못한다). | 기능을 만들지 않는다. | **결정(STA-47): 제거.** 트리거는 전역 단축키뿐. 문구 `captureSelected`도 제거. | ☑ |
| D-06 | 이름 바꾼 단축키가 다른 앱과 충돌해 등록에 실패할 때의 사용자 메시지(`shortcut_registration_failed`)가 레거시에서는 영어 원문이다. | 한국어 문구 추가. | **결정(STA-55): 한국어·영어 문구 `shortcutRegistrationFailed` 추가.** | ☑ |
| D-07 | 메인 창을 닫았을 때 앱이 종료되는지, 메뉴 막대에 남는지가 레거시에서 확인되지 않았다. 메뉴 막대와 전역 단축키의 목적상 남는 편이 자연스럽다. | 메뉴 막대에 남는다. 마지막 창을 닫아도 종료하지 않고 전역 단축키와 메뉴 막대 항목을 유지한다. 종료는 Cmd+Q. (STA-52) | | ✔ |
| D-08 | 로그인 시 자동 실행, Dock 아이콘 표시 여부는 정의되어 있지 않다. | 범위 밖. 필요하면 새 이슈. | | ☑ |
| D-09 | `Design.md`와 `design-system.md`의 일부 문장은 AppKit 도구 막대, `compactSearch`, `inspectorOverlay` 같은 Tauri 구현 용어를 쓴다. | Swift 구현이 안정되면 문서에서 해당 구현 용어를 제거. | **결정(STA-64): 두 문서를 SwiftUI·AppKit 기준으로 다시 씀. 색·서체·모양 토큰은 코드의 시스템 색·텍스트 스타일·기본 컨트롤에 맞추고, 레이아웃 수치는 유지. 동작 줄이기 시 인스펙터 오버레이 슬라이드 제거.** | ☑ |
| D-10 | STA-38에서 도입한 SF Symbols 렌더링, 포커스 링, 제목 인라인 이름 변경, 목록 비포커스 선택 약화, 설정 화면 토글은 **실제 앱에서 확인되지 않았다.** | 레거시 앱에서 확인하지 말고 Swift 구현에서 기준(서체관리자)으로 직접 확인. | | ☑ |
| D-11 | 라이트 테마의 도구 막대와 960 pt 너비 실화면 확인이 남아 있다. | Swift 구현에서 확인. | | ☑ |
| D-12 | 문구 `shortcutFormatHint`가 "Tauri 형식"이라고 안내한다. 저장 문자열은 호환을 위해 같은 형식(`Shift+Cmd+K`)을 쓰지만 사용자에게 구현 용어를 보이면 안 된다. | 문구에서 Tauri를 빼고 형식 예시만 안내. | **결정(STA-55): `shortcutFormatHint`를 "수식키와 키를 +로 연결, 예: Shift+Cmd+K, F21–F24 미지원"으로 교체.** | ☑ |
| D-17 | 메뉴 막대 저장 피드백(`Saved`/`Error` 제목 900 ms), 도구 막대 구성, 시스템 강조색, 태그 아이콘이 소유자가 2026-10-15 채택한 브랜드·UI v2와 다르다. | 문서를 먼저 고치고 구현은 후속 이슈로 나눈다. | **결정(PLO-89): 메뉴 막대는 점·체크·느낌표 기호 피드백(T-03, T-05), 도구 막대 축소, 강조색 `#2F6BFF`/`#4F8CFF`, 태그 `number`·`#` 표기, 새 앱 아이콘(U 항목).** | ☑ |

## 4단계 수동 확인 기록 (STA-47, 2026-10-08)

실제 앱(`make-app.sh debug` 번들, 저장 폴더·설정 파일은 `/tmp`로 분리)에서 확인한 범위입니다. 일부만 확인한 항목은 ☐로 두었습니다.

| 확인한 내용 | 결과 | 관련 항목 |
| --- | --- | --- |
| 메모에서 선택 후 `Shift+Cmd+C` → 팝업 → 노트·태그 입력 → 저장 | 정상. `drop.json` 키 집합과 `null` 규칙, `content.md`, `note.md`, `recentTags` 갱신, 출처(앱·윈도우 제목) 확인 | P-10, M-01, S-01, I-02 |
| Safari 본문 선택(접근성 읽기 불가 → 폴백) → 팝업에 선택 텍스트 → 저장·취소 후 붙여넣기 | 정상. 캡처 전 클립보드 텍스트가 그대로 복원됨 | P-17, P-04(성공 경로), P-09(텍스트만) |
| 권한을 초기화한 뒤 다시 허용 | 같은 번들 ID(당시 `app.notedrop.dev`)의 레거시 Tauri 앱이 있으면 이전 허용 항목과 새 빌드 서명이 맞지 않아 권한이 없다고 나올 수 있음. `tccutil reset Accessibility app.notedrop.dev` 후 재허용 | C-12, A-01 |

이어서 사용자가 목록의 나머지 수동 항목(메모에서 클립보드 불변, Chrome URL, 선택 없음, 권한 해제, 팝업이 열린 채 단축키,
한글 조합 중 Enter, 터미널 폴백)이 모두 동작한다고 보고했습니다. 항목별 출력은 남기지 않았고 사용자 보고에 근거합니다.

**범위 밖으로 확인된 것**: 이미지, 텍스트와 이미지가 함께 있는 클립보드의 **저장**은 4단계 범위가 아닙니다. 선택 텍스트 캡처는
텍스트 Drop만 만들고(스펙 3.1), 이미지와 `mixed`는 클립보드 캡처(스펙 3.2, K-01~K-06, 메뉴 막대 `Save Clipboard`)와 팝업의
이미지 미리보기·유형 선택이 필요해 5단계에서 구현합니다(STA-47에서 확정). 이미지가 들어 있던 클립보드를 텍스트 캡처 뒤에
복원하는 동작(P-09)은 이번에 따로 확인하지 않았습니다.

## 호환성 검증 절차

1. [픽스처](fixtures/README.md)의 폴더를 임시 저장 폴더로 복사하고 설정의 `storageFolderPath`를 그 폴더로 지정한다.
2. 앱을 실행해 모든 Drop이 표시되는지(깨진 것은 경고만) 확인한다.
3. 각 Drop을 수정하고 저장한 뒤 `drop.json`의 키 집합과 `null` 규칙(S-01)이 유지되는지 확인한다.
4. 새 Drop을 저장해 ID, 시각, 파일 구성이 S-05~S-11을 만족하는지 확인한다.
5. 실제 사용자 폴더로는 먼저 **복사본**에서 같은 확인을 반복한다. 원본 폴더를 처음부터 쓰지 않는다.

## 부분 확인 (STA-41)

- S-16: 휴지통 이동 주입으로 성공·실패 단위 테스트만 확인했습니다. 실제 `FileManager.trashItem` 동작은 STA-77에서 확인했습니다(아래 기록).
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

수동 확인이 남음(실제 앱): 테마 변경이 메인 창과 Save Popup에 즉시 적용되고 `system`으로 돌아가면 풀리는지(C-10), 재실행 후 유지, 설정 화면에서 사이드바 접힘·너비가 Library와 같은지(L-06). `PLOPCUT_APPEARANCE`는 테마가 `system`일 때만 적용되는 개발용 재정의로 남겨 둠.


## 5단계 클립보드 캡처 기록 (STA-56)

메뉴 막대 `Save Clipboard`로 텍스트 클립보드를 캡처한다. K-01, K-02, K-03, K-05는 단위 테스트(`ClipboardCaptureTests`)로 확인함. 이미지와 `mixed` 저장은 STA-57에서 들어왔다(아래 기록).

수동 확인이 남음(실제 앱): K-06(실패 시 `Error`만 보이고 메인 창이 뜨지 않음), 메뉴 항목에서 팝업이 열리고 저장되는지, plopcut이 앞일 때 출처가 비는지.

## 5단계 저장 폴더와 첫 실행 기록 (STA-53)

설정 화면에 저장 폴더 경로와 `저장 폴더 선택` 버튼이 있다. 폴더를 바꾸면 `storageFolderPath`만 바뀌고 기존 Drop은 옮기지 않으며, 이후 스캔과 저장은 설정을 매번 읽어 새 폴더를 쓴다(S-17). 바꾸기 직전에 편집 중인 내용을 먼저 저장하고, 바꾼 뒤 Library를 다시 스캔한다. 선택을 취소하면 `folderCancelled` 안내가 나온다.

첫 실행(`hasCompletedFirstRun == false`)에는 닫을 수 없는 모달이 뜬다. `기본 폴더 사용`은 폴더를 만들고 `folderConfirmed`, `폴더 선택`은 선택한 폴더를 저장하고 `folderSet`을 보인 뒤 `hasCompletedFirstRun = true`로 저장한다. 선택을 취소하거나 폴더를 쓸 수 없으면 모달이 남는다.

폴더 판정(`StorageFolderCheck`): 폴더가 있으면 디렉터리이고 쓸 수 있어야 한다. 없는 폴더는 가장 가까운 상위 폴더가 쓸 수 있을 때만 통과한다(저장 때 `drops/`가 만들어지므로). 통과하지 못하면 설정 화면에 `storageFailure`를 보이고, 저장 팝업의 저장도 같은 판정으로 막는다.

개발용 `PLOPCUT_STORAGE_FOLDER`는 설정보다 우선한다. 폴더 변경을 확인하려면 이 변수 없이 `PLOPCUT_SETTINGS_FILE`만 지정해 실행한다. `PLOPCUT_SETTINGS_FILE`은 이제 저장 폴더 해석에도 쓰인다.

단위 테스트(`StorageFolderCheckTests` 7개, `StorageFolderModelTests`·`StorageRootResolutionTests` 14개)로 확인함. 수동 확인이 남음(실제 앱): 폴더 선택 대화상자, 선택 취소 안내, 빈 설정 파일에서 첫 실행 모달(기본 폴더/폴더 선택/취소 시 모달 유지), 폴더 변경 후 Library와 새 저장이 새 폴더를 쓰는지, 쓸 수 없는 폴더의 안내.

## 5단계 권한 상태 기록 (STA-54)

설정 화면에 손쉬운 사용·클립보드·자동화 세 항목의 상태(허용/권한 필요/알 수 없음), 설명, 다음 행동을 보여 준다. 손쉬운 사용이 없으면 `시스템 설정 열기` 버튼이 시스템 설정의 손쉬운 사용 화면으로 이동한다. 자동화는 항상 `알 수 없음`이고 Chrome URL을 처음 읽을 때 macOS가 묻는다는 안내(`permissionAutomationNote`)를 붙인다. 앱이 다시 활성화될 때(`didBecomeActive`) 상태를 다시 읽는다.

단위 테스트(`PermissionsModelTests`, 8개)로 확인함: 손쉬운 사용·클립보드 판정(A-01, A-02), 자동화 항상 알 수 없음(A-03), 항목×상태 문구 키와 두 언어 존재(N-04), 시스템 설정 버튼은 손쉬운 사용이 없을 때만, 갱신 시 변경 반영.

수동 확인이 남음(실제 앱): A-01~A-04 모두. 손쉬운 사용을 켜고 끈 뒤 앱으로 돌아오면 화면이 갱신되는지, 버튼이 시스템 설정 손쉬운 사용 화면을 여는지, 권한이 없어도 앱이 종료되지 않는지. 클립보드는 `NSPasteboard`에 권한 조회 API가 없어 텍스트를 실제로 읽을 수 있으면 허용, 텍스트가 있는데 읽지 못하면 권한 필요, 비었거나 텍스트가 아니면 알 수 없음으로 표시한다(A-02). 설정 화면을 열 때와 앱이 활성화될 때 다시 읽는다.


## 5단계 단축키 변경 기록 (STA-55)

설정 화면의 `선택 텍스트 단축키` 섹션에서 바꾼다. 순서는 새 단축키 등록 → 이전 해제 → 설정 저장이며(`ShortcutController`), 등록 실패나 저장 실패면 이전 단축키가 계속 동작하고 설정 파일은 바뀌지 않는다. 저장 실패 뒤 이전 단축키를 다시 등록하지 못하면 `shortcut_rollback_failed`로 알린다. 거절된 입력은 필드에 남지 않고 동작 중인 단축키로 되돌아간다. 시작 시에는 저장된 단축키 하나만 등록하고, 실패하면 오류를 보관하고 메뉴 막대에 `Error`를 보인다(C-09). 새 오류 문구는 한국어·영어로 `shortcutRegistrationFailed`, `shortcutRollbackFailed`를 추가했고, 형식 오류는 `shortcutFormatHint`를 보인다. Carbon 핫키는 등록마다 고유 id를 붙여 교체 중 두 핫키가 동시에 살아 있어도 누른 쪽만 동작한다.

수동 확인이 남음(실제 앱): 단축키 변경 직후 새 단축키로 캡처되고 이전 것은 반응하지 않는지, 다른 앱이 쓰는 조합으로 바꾸면 한국어 오류가 나오고 이전 단축키가 계속 되는지, 재실행 후 유지되는지, F21–F24 입력 시 형식 안내가 나오는지.

## 단축키 키 녹화와 저장 전 미적용 기록 (STA-69, STA-70)

STA-70 원인: 단축키 입력란 `TextField`에 `.onSubmit { model.apply() }`가 붙어 있었다(`ShortcutSection.swift`). 입력란에서 Return을 누르면 `ShortcutModel.apply()` → `CaptureRuntime.changeShortcut` → `ShortcutController.change`가 바로 실행되어 새 단축키 등록, 이전 해제, `settings.json` 저장까지 끝났다. `저장` 버튼을 누르지 않아도 적용된 것이다. 확인용 SwiftUI 프로브(macOS 26)에서 `onSubmit`은 Return에서만 불리고 포커스 이동에서는 불리지 않았다. 또 `ShortcutModel.text`는 앱 전체에서 하나라 저장하지 않고 설정 화면을 떠나도 입력한 문자열이 그대로 남아, 돌아오면 적용된 것처럼 보였다.

바꾼 점:

- 입력란을 키 녹화 필드로 바꿨다. 필드를 누르면 녹화가 시작되고, 누른 키 조합은 `ShortcutRecording.interpret`(키 코드와 수식 키 플래그를 받는 순수 함수)가 저장 문자열로 바꾼다. 키 이름은 등록할 때 쓰는 `KeyCodes` 표를 거꾸로 읽으므로 한글 입력 상태나 자판 배열과 관계없이 누른 물리 키로 등록된다. 수식 키는 `Ctrl+Option+Shift+Cmd` 순서로 쓰며, 레거시 파서(global-hotkey 0.8)가 읽는 토큰만 쓴다.
- 수식 키만 누르면 필드에 `Shift+Cmd+`처럼 미리보기만 보이고 확정하지 않는다. 수식 키 없는 키는 `shortcutNeedsModifier`, D-03 범위 밖의 키(문장부호, 숫자 키패드, Help 등)는 `shortcutUnsupportedKey`를 보이고 녹화를 계속한다. Esc만 누르거나, 다른 곳을 클릭하거나, 다른 창이 키 창이 되거나(`NSWindow.didResignKeyNotification`), 다른 앱으로 전환하면 녹화를 끝낸다. 녹화가 끝나지 않은 채 포커스가 옮겨져 다른 창의 키 입력까지 삼키는 일을 막기 위해서다. F21–F24는 Mac 키보드로 누를 수 없고, 손으로 고친 설정 파일의 F21–F24는 지금처럼 등록에서 거부되어 `shortcutFormatHint`를 보인다.
- 녹화 중에는 `NSEvent` 로컬 모니터가 키 입력을 먼저 가져가므로 메뉴 단축키(Cmd+Q, Cmd+W 등)와 포커스된 버튼(Space)으로 가지 않는다. 기록을 끝낸 키를 계속 누르고 있을 때 생기는 자동 반복도 버린다(Cmd+Q를 녹화하다 앱이 종료되지 않도록). 이 기억은 키를 떼거나, 수식 키가 바뀌거나, 새로 키를 누르거나, 클릭·포커스 이동·새 녹화 때 지운다. 그래서 키 떼기 이벤트를 놓쳐도 이후 입력을 계속 삼키지 않는다. 녹화 중 자동 반복은 해석하지 않고 버려서 거부 안내가 깜빡이지 않는다. 이 판정은 순수 상태기계 `RecorderKeyRouter`에 있고, `ShortcutKeyMonitor`는 `NSEvent`를 넘기고 결과만 적용한다.
- 지금 등록된 전역 단축키는 Carbon이 키 입력을 가져간다. 녹화 중에 눌리면 캡처하지 않고 "지금 단축키 유지"로 처리해 고른 조합을 비우고 저장할 것이 없는 상태로 둔다(`CaptureRuntime.shortcutPressed` → `ShortcutModel.currentShortcutPressed`). 핫키 콜백은 `GlobalHotKey`가 메인 큐로 넘긴 뒤 `@MainActor` 동작을 부르므로 메인 액터에서 실행된다. 캡처 경로에서는 설정 화면이 이미 만든 모델만 확인하고, 모델을 새로 만들거나 설정을 읽지 않는다. 롤백 실패나 시작 시 등록 실패로 등록된 단축키가 없으면 핫키가 울리지 않는다. 이때 같은 조합은 일반 키로 녹화되어 저장 대기로 남고, 다시 저장할 수 있다.
- 고른 조합은 `ShortcutModel.draft`에만 있고, `저장`을 눌러야 `ShortcutController.change`(등록 → 해제 → 저장)를 한 번 실행한다. 입력란 Return 적용(`onSubmit`)은 없앴다. `취소` 버튼과 설정 화면 이탈은 고른 조합을 버린다. 저장하지 않은 조합이 있으면 `shortcutUnsaved` 안내를 보인다. 같은 조합을 다시 골라도 저장할 수 있어서, `shortcut_rollback_failed` 뒤 다시 설정할 수 있다.
- STA-83: Esc로 녹화를 끝내도 `shortcutNeedsModifier`/`shortcutUnsupportedKey` 안내가 남던 문제. 원인은 안내가 `errorMessage`에 담겨 있는데 `ShortcutModel.cancelRecording()`이 이를 지우지 않았기 때문이다. 이제 안내가 녹화 전용인지 기억해 두었다가 녹화가 끝나는 모든 경로(Esc, 클릭, 키 창 변경, 앱 전환, 조합 확정, 지금 단축키 누름)가 지나는 `cancelRecording()`에서 지운다. 등록 실패 문구 등 다른 안내는 그대로다. `ShortcutModelTests`로 각 경로를 확인함. 실제 앱 확인(Esc, 앱 전환 뒤 안내 없음)은 남음.
- 새 문구(en/ko): `shortcutField`, `shortcutRecording`, `shortcutRecordHint`, `shortcutUnsaved`, `shortcutNeedsModifier`, `shortcutUnsupportedKey`.

단위 테스트로 확인함: `ShortcutRecordingTests`(10개, `KeyCodes` 키 코드 중복 없음 포함), `RecorderKeyRouterTests`(9개, 포커스 이동·클릭 시 녹화 종료, 자동 반복과 키 떼기 유실 처리), `ShortcutModelTests`(15개, 실제 `ShortcutController`와 가짜 등록기로 저장 전에는 등록·저장이 호출되지 않음, 지금 단축키를 눌렀을 때 저장 대기 없음, 롤백 실패 뒤 같은 조합 재저장을 확인).

적용하지 않은 것: 등록 실패나 롤백 실패 뒤에도 고른 조합을 남겨 재시도를 쉽게 하는 안은 적용하지 않았다. STA-55와 C-06의 "거절된 입력은 필드에 남지 않는다"를 지키기 위해서다. 실패 뒤에는 동작 중인 단축키로 되돌린다.

수동 확인이 남음(실제 앱): 아래 확인 전까지 C-06, C-08을 ☐로 둔다.

1. 설정 → `선택 텍스트 단축키` 필드를 누르면 테두리가 강조되고 `키를 누르세요`가 보인다. Shift+Cmd를 누르고 있으면 `Shift+Cmd+`가 보이고 떼면 다시 안내로 돌아간다.
2. Shift+Cmd+K를 누르면 필드가 `Shift+Cmd+K`, `아직 저장하지 않았습니다…` 안내가 보인다. 이 상태에서 다른 앱의 텍스트를 선택하고 Shift+Cmd+C를 누르면 캡처되고 Shift+Cmd+K는 반응하지 않는다. `settings.json`의 `selectedTextShortcut`은 그대로다.
3. `저장`을 누르면 Shift+Cmd+K로 캡처되고 Shift+Cmd+C는 반응하지 않으며 `settings.json`이 바뀐다. 재실행 후에도 유지된다.
4. 녹화 중 K만 누르면 수식 키 안내, Cmd+-(빼기)나 숫자 키패드 키는 쓸 수 없는 키 안내가 나오고 녹화가 계속된다. Esc를 누르면 녹화가 끝나고 필드는 이전 값이다.
5. 녹화 중 Cmd+Q, Cmd+W, Cmd+,를 누르면 앱이 종료되거나 창이 닫히지 않고 필드에 그 조합이 보인다. Cmd+Q를 길게 누르고 있어도 앱이 종료되지 않는다. 저장하지 않고 `취소`.
6. Shift+Cmd+K를 고른 뒤 다시 녹화하면서 지금 단축키(Shift+Cmd+C)를 누르면 캡처나 팝업이 뜨지 않고, 필드는 `Shift+Cmd+C`, 미저장 안내는 사라지고 `저장`은 비활성이다.
7. 조합을 고른 뒤 저장하지 않고 사이드바에서 Library로 갔다가 설정으로 돌아오면 필드가 이전 단축키이고, 이전 단축키로 캡처된다. `취소` 버튼도 같다.
8. 다른 앱이 쓰는 조합을 녹화하고 저장하면 `shortcutRegistrationFailed` 문구, 필드는 이전 값, 이전 단축키 동작.
9. 한글 입력 상태에서 녹화해도 영문 키 이름(예: `Shift+Cmd+K`)으로 기록된다.
10. 녹화 중 다른 plopcut 창이나 다른 앱 창을 클릭하거나 키 창을 바꾸면 녹화가 끝나고, 그 창에서 키 입력(Library 목록 이동, 노트 입력)과 전역 단축키 캡처가 정상 동작한다.

## 5단계 이미지와 mixed 저장 기록 (STA-57)

`Save Clipboard`로 이미지만 있는 클립보드는 `image` Draft, 텍스트와 이미지가 함께 있으면 `mixed` Draft가 된다. Save Popup은 이미지 미리보기를 보여 주고, `mixed`는 텍스트/이미지 분할 선택(기본 텍스트)을 주며 고른 유형 하나만 저장한다(D-02). 이미지는 `DropStore.saveImage`로 `image.png`에 저장하고, 비었거나 PNG가 아닌 이미지는 저장하지 않고 이유를 보여 준다(S-10). 캡처 단계에서도 PNG 시그니처가 아니면 `clipboard_image_unavailable`로 취급해 텍스트가 있으면 경고와 함께 텍스트로 진행한다. 임시 오류 코드 `clipboard_image_unsupported`와 문구 `clipboardImageUnsupported`는 제거했다.

단위 테스트로 확인함: 분류와 제목(`ClipboardCaptureTests`), 비PNG 바이트 거부, 팝업의 유형 선택과 저장 요청(`SavePopupImageTests`).

수동 확인이 남음(실제 앱): K-04(스크린샷 PNG와 TIFF를 내는 앱에서 저장), 이미지만/텍스트+이미지 클립보드에서 팝업 미리보기와 선택, 저장한 이미지 Drop이 Library 본문에 보임, P-09(선택 텍스트 캡처 전후로 이미지만/텍스트만/둘 다 있던 클립보드 복원). 폴백 복원은 TIFF만 있던 클립보드를 PNG로 되돌린다.

## 5단계 instant 모드 기록 (STA-58)

저장 확인 방식(`captureConfirmationMode`)이 캡처 동작에 연결됐다. 단축키와 `Save Clipboard` 모두 같은 경로(`CaptureRouter`)를 지나며, 모드는 캡처마다 설정 파일에서 읽어서 재시작 없이 반영된다(읽을 수 없으면 팝업). `instant`에서 텍스트 Draft는 팝업 없이 노트 `""`·태그 없음으로 저장되고, 메뉴 막대에 `Saved`가 900 ms 보이고, Library가 새로고침되며 새 Drop이 선택된다. 이미지와 `mixed`는 `instant`에서도 팝업이다. 즉시 저장이 실패하면 오류를 보관하고(메인 창을 띄우지 않음) `Error`를 보인다. 즉시 저장은 태그가 없으므로 `recentTags`를 갱신하지 않는다.

단위 테스트로 확인함: 모드×유형 결정(`CaptureConfirmationTests`), 즉시 저장 요청 모양·팝업 경로·모드 재읽기·실패 보고(`CaptureRouterTests`), `Saved`/`Error` 900 ms와 교체(`MenuBarTests`).

수동 확인이 남음(실제 앱): `instant`로 바꾼 뒤 텍스트 선택 캡처(`Shift+Cmd+C`)와 `클립보드 저장`이 팝업 없이 저장되고 `Saved`가 보이며 Library에 새 Drop이 선택됨, 이미지·mixed는 `instant`에서도 팝업, `modal`로 되돌리면 다시 팝업, 저장 폴더를 쓸 수 없을 때 `Error`가 보이고 다음에 메인 창을 열면 오류가 한 번 나옴.

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
- N-03: `LocalizationTests`의 알려진 코드 15개(코드별로 기대하는 문구 키까지 확인)와 알 수 없는 코드. **레거시와 다르게 정한 두 가지**: (1) 알 수 없는 코드의 오류는 레거시처럼 원본 메시지를 보여 주지 않고 기본 문구(`defaultError`)를 보여 준다. Swift의 `PlopcutError.detail`은 사람용 문장이 아니라 로그용 원문(파일 경로, OS 영어 문구)이라 그대로 보여 주면 한국어 UI에 섞이고 경로가 노출된다. (2) "문자열 오류는 그대로"는 Swift에 문자열 오류 타입이 없어 해당 없음이고, `PlopcutError`가 아닌 오류는 기본 문구로 가린다. 이 확인 중 `clipboard_restore_failed`, `automation_*` 문구를 추가했고 `empty_image`를 레거시처럼 `invalidImage`로 맞췄다.

P-02는 실제 대기 시간을 보는 수동 항목이라 ☐로 남긴다.

## Library 조작 수동 확인 기록 (STA-62)

2026-10-08 사용자가 실제 앱에서 확인했다. L-11, L-12, L-13, L-14를 ☑로 바꿨다.

- 처음 확인에서 우클릭 메뉴에 `Markdown 내보내기`와 구분선이 없고 `내용 복사`가 휴지통 뒤에 있었다. L-11 순서(출처 열기, 내용 복사, Markdown 내보내기, 구분선, 휴지통)로 고쳤다. 내보내기 로직은 상세 화면 버튼과 메뉴가 `LibraryModel.exportWithPanel`을 함께 쓴다.
- `Cmd+Backspace`는 처음에 아무 반응이 없었다. 목록 뷰의 키 핸들러(`onKeyPress`)로는 `Cmd` 조합이 도달하지 않아서, 목록에 포커스가 있을 때만 활성화되는 메뉴 명령 `휴지통으로 이동`(⌘⌫, `TrashCommand`)으로 바꿔 동작을 확인했다. 노트·태그 입력창에서는 메뉴 항목이 비활성이라 글자 지우기가 그대로 동작한다.
- 출처 열기(URL 없을 때 비활성)와 Markdown 내보내기 취소(파일 미생성)는 이상 없음.

## 체크리스트 정리 A 묶음: 단위 테스트 근거 (STA-63)

- C-01: `SettingsTests.theSettingsFileLivesInApplicationSupportWhateverTheStorageFolderIs`. 기본 경로가 `~/Library/Application Support/plopcut/settings.json`이고, 저장 폴더를 바꿔도 설정 파일이 옮겨지지 않으며 새 폴더에 파일이 생기지 않는다.
- C-07: `SettingsTests.aFailedWriteKeepsTheOldFileAndLeavesNoTempFile`(쓰기 실패 시 `settings_unwritable`, 기존 파일 그대로, 임시 파일 없음. root에서는 권한 검사가 맞지 않아 건너뜀), `writtenFileUsesContractKeysAndLeavesNoTempFiles`(성공 시 임시 파일 없음), `concurrentUpdatesAreSerialized`(동시 갱신 직렬화).
- M-03: `SelectedTextCaptureTests.sourceFailureNeverBlocksCapture`(출처 수집 실패가 캡처를 막지 않음)와 `DropStoreTests`의 `drop.json` 확인(비어 있는 출처 필드는 `null`로 저장).
- P-02: `SelectedTextCaptureTests.pollingIsEveryTwentyFiveMillisecondsForSevenHundred`(25 ms, 700 ms, 28회)와 `timesOutAfterTwentyEightPollsAndRestores`. 실제 폴백 동작은 STA-47 수동 확인(Safari)에서 확인됨.

## 결정 사항 기록 (STA-63, 2026-10-08)

사용자가 아래와 같이 결정했고, 해당 항목을 ☑(결정 완료)로 바꿨다.

- P-15: 레거시의 `swift -e` 서브프로세스 클립보드 접근 구조는 이어받지 않는다. `NSPasteboard`를 직접 쓰고 같은 동작만 유지한다(이미 그렇게 구현됨).
- M-04: 파일 경로는 수집하지 않는다. 신뢰할 수 있는 API가 없어 `filePath`는 항상 `null`이다(현재 구현 그대로).
- D-01: 클립보드 캡처 단축키(`Shift+Cmd+V`)는 만들지 않고 메뉴 막대 `Save Clipboard`만 둔다. 단축키는 별도 요청이 있을 때 새 이슈로 한다.
- D-02: `mixed` Drop 폴더는 레거시와 같게 깨지지 않고 목록에만 표시한다. 본문과 이미지 표시는 필요할 때 새 이슈로 한다. 새로 저장하는 Drop은 `text` 또는 `image`뿐이다.
- D-03: 단축키 허용 범위는 현재 구현 그대로다. `Shift/Cmd/Ctrl/Option` 조합에 문자, 숫자, `F1`~`F24`(등록은 `F21`~`F24`를 거부하고 안내), 방향키, `Space`, `Enter`, `Tab`, `Escape`, `Backspace`, `Delete`, `Home`, `End`, `PageUp`, `PageDown`을 받고 나머지는 거부한다.
- D-04: 이미지 Drop은 읽기에서 `drop.json`의 `imagePath`를 우선하고(없으면 `image.png`), 쓰기는 항상 `image.png`다.
- D-08: 로그인 시 자동 실행과 Dock 아이콘 표시 여부는 범위 밖이다. 현재 동작(메뉴 막대에 남고 Dock에도 보임, 자동 실행 없음)을 유지하고 필요하면 새 이슈로 한다.
- D-09: 디자인 문서의 Tauri 구현 용어 정리는 별도 이슈 STA-64로 이관했다.

## B 묶음 수동 확인 기록 (STA-63)

사용자가 실제 앱(ad-hoc 서명 디버그 빌드)에서 직접 확인했고 모두 문제가 없다고 보고했다.

- P-13: 선택 없이 `Shift+Cmd+C` 시 메뉴 막대 `Error`, 메인 창 표시, 보관 오류 알림, 창을 닫고 다시 열면 알림이 다시 뜨지 않음.
- T-04: 조용한 실패(`pbcopy < /dev/null` 뒤 `클립보드 저장`) 후 메뉴 막대로 메인 창을 열면 보관 오류가 한 번 표시됨. 이 확인을 준비하다가 메뉴 막대로 열 때는 보관 오류를 보여 주지 않던 결함을 찾아 `CaptureRuntime.showMainWindow`에서 한 번 꺼내 보이도록 고쳤다.
- C-12: 번들 ID를 바꾼 복사본에서 손쉬운 사용이 `권한 필요`로 나오고, Drop과 설정은 그대로.
- I-05, D-10: SF Symbols, 포커스 링, 제목 인라인 이름 변경, 목록 비포커스 선택 약화, 설정 화면 토글.
- D-11: 라이트 테마 도구 막대와 960 pt 최소 너비.

## Save Popup 노트 커서와 컴팩트 배치 기록 (STA-66, STA-67)

노트 커서(STA-66) 원인은 두 가지였다. 실제 SwiftUI `TextEditor`를 창에 띄우고 입력기와 같은 호출(`setMarkedText`, `insertText`)로 재현했다.

- 한 키 입력에서 앞 음절을 확정하고 다음 음절을 조합으로 여는 순간(예: `한` 확정 + `ㄱ` 조합), 다음 화면 갱신에서 `TextEditor`가 바인딩 값을 텍스트 뷰에 다시 써서 조합 중인 글자가 사라지고 커서가 한 칸 앞으로 돌아갔다. 조합만 있고 바인딩이 바뀌지 않은 갱신에서는 생기지 않았다.
- 자리 표시 문구가 커서보다 5 pt 아래에 있었다(`padding(9)`, 커서는 위 여백 0). 조합 중에는 바인딩이 비어 있어 첫 음절과 자리 표시 문구가 겹쳤다.

노트 입력을 `PopupNoteEditor`(AppKit `NSTextView`)로 바꿨다. 조합 중에는 텍스트 뷰에 쓰지 않고, 바인딩에는 보이는 글자(조합 포함)를 넣으며, 자리 표시 문구는 텍스트 뷰가 커서 위치에 직접 그린다. 단위: `SavePopupWindowTests.NoteEditor`.

컴팩트 배치(STA-67): 실제 창 높이는 제목 막대 32를 더한 592였고, 경고·태그 칩·최근 태그가 많으면 고정 프레임 밖으로 넘쳐 버튼과 제목이 잘렸다. 표시 항목은 그대로 두고 유형 선택을 제목 줄로, 출처 레이블을 값 옆으로 옮겼으며 간격·미리보기(120→96)·노트(78→60) 높이를 줄였다. 높이는 내용에 맞춰 최소 388(창 420)이고 내용이 늘면 아래로 커진다. 창은 화면의 보이는 영역보다 커지지 않고 그 안에 머물며, 넘치는 입력 영역은 스크롤되고 저장·취소 버튼은 아래에 고정된다. 커진 창을 새 Draft로 다시 열면 그 Draft의 크기로 중앙에 놓인다. 단위: `SavePopupWindowTests.Layout`.

코드 리뷰 반영: 노트에서 Tab·Shift+Tab은 탭 문자 대신 태그 필드와 노트 사이를 오간다(기존 `TextEditor`는 탭 문자를 넣었다. 레거시 textarea는 포커스 이동). Option+Tab은 탭 문자. `Cmd+Enter` 저장은 먼저 조합 중인 글자를 확정한다. 포커스 상태 변경은 다음 차례로 미룬다. 단위: `SavePopupWindowTests.NoteEditor`(Return, Tab, Escape, `Cmd+Enter` 포함).

수동 확인이 남음(실제 앱): 한글 노트 입력(줄바꿈, 문장 중간 커서, 노트↔태그 포커스 이동), 자리 표시 문구 위치, 텍스트·이미지·mixed 팝업에서 잘림 없음, 태그 칩이 늘 때 창이 아래로 커지고 화면 아래에 닿으면 입력 영역이 스크롤되는지, 실제 한글 입력기에서 조합 중 `Cmd+Enter`, Tab 이동, Escape, 라이트·다크 테마.

## 스크롤 막대 두께 기록 (STA-68)

AppKit의 레거시 스크롤 막대는 너비 17(knob 11)이고 `controlSize = .small`이면 13(knob 7)이다. `.mini`도 세로 스크롤러는 13이라 `.small`을 쓴다. 이 값은 이 기기(시스템 설정 스크롤 막대 '항상')에서 `NSHostingView`에 띄운 `ScrollView`와 `List`로 재서 확인했다. 스크롤러 서브클래스로 더 얇게 만드는 방법은 막대와 knob를 직접 그려야 해서 택하지 않았다. `SlimScroller`(`.slimScrollers()`)는 스크롤러의 `controlSize`만 바꾼다. 스크롤 막대 스타일(legacy/overlay)과 자동 숨김, 드래그는 시스템 설정을 따른다. overlay 스타일의 막대는 원래 얇고 스크롤할 때만 나타나므로 줄어드는 효과는 legacy 스타일(마우스 연결 또는 '항상')에서 나타난다.

검토 반영: `PopupNoteEditor`의 스크롤 뷰는 `tile()`마다 작은 스크롤러를 다시 설정한다(새 스크롤러는 regular로 시작하고 AppKit이 그 뒤에 `tile()`을 부른다). 프로브는 레이아웃과 시스템 스크롤 막대 설정 변경 알림에서 다시 적용하고, 대상을 못 찾으면 같은 크기에서 4번까지만 창을 훑는다. 프로브는 마우스와 접근성에서 숨긴다. 툴바가 있는 분할 보기에 Library 목록을 띄운 테스트 창(제목 막대 투명, `fullSizeContentView`)에서도 목록의 스크롤러가 작게 바뀌었다. 겹침 기준은 0.75다.

적용: Save Popup(바깥 입력 영역, 텍스트 미리보기, `PopupNoteEditor`), Library Drop 목록, Drop 본문, 인스펙터와 그 노트 `TextEditor`. 사이드바 목록은 제외했다. 단위: `SlimScrollerTests`.

수동 확인이 남음(실제 앱): 시스템 설정 → 모양 → 스크롤 막대 표시를 '항상'으로 두고 Save Popup 세 영역과 Library 목록의 막대가 이전보다 얇은지, knob를 마우스로 끌 수 있는지, '스크롤할 때'와 '마우스나 트랙패드 연결에 따라 자동'에서 막대가 시스템 방식대로 나타나고 사라지는지, 라이트·다크 테마.

## 저장소 호환성 검증 기록 (STA-77)

S·C 항목을 픽스처 **복사본**으로 다시 확인하고 항목마다 Swift 테스트 근거를 남겼다. 새 테스트는
`PlopcutCore/Tests/PlopcutCoreTests/CompatibilityTests.swift`에 있다. 나머지는 기존 `DropStoreTests.swift`,
`NamingTests.swift`, `SettingsTests.swift`(Core)와 앱 테스트다.

| ID | 근거 (Swift 테스트) |
| --- | --- |
| S-01 | `savesTextDropInContractFormat`, `savedFilesMatchTheFixtureShape`, `editingAMinimalTextDropWritesTheFullContract`, `editingAMinimalImageDropRecordsImagePng` |
| S-02 | `minimalTextDropGetsDefaults`, `aMissingRequiredKeySkipsOnlyThatDrop`(필수 키 5개 각각), `nullOptionalKeysReadLikeMissingKeys` |
| S-03 | `scansFixturesInExpectedOrder`, `everyFixtureScansAsTheReadmeExpects`(경고 1개, 메시지에 `broken-json`) |
| S-04 | `scansFixturesInExpectedOrder`(같은 `createdAt`은 `id` 내림차순), `newDropsSortAmongLegacyDrops` |
| S-05 | `TimestampTests.stringOrderMatchesTimeOrder`, `closeTimesSortAsStrings`(마이크로초 간격 50개), `nowIsNineDigitsAndAfterLegacyStamps`, `savesTextDropInContractFormat` |
| S-06 | `idFormat`, `collidingIdsGetNumericSuffix` |
| S-07 | `slugRules`, `slugLowercasesBeforeFiltering` |
| S-08 | `TitleTests.priority`, `truncatesTo80`, `savesImageDrop` |
| S-09 | `savesTextDropInContractFormat`, `rejectsBlankText` |
| S-10 | `rejectsEmptyAndNonPngImages` |
| S-11 | `savesTextDropInContractFormat`, `newImageDropsAlwaysGetANoteFile`, `clearingNoteOverwritesFile` |
| S-12 | `blankNoteIsNoNoteAndRealNoteIsKept`, `whitespaceOnlyNoteIsNoNote` |
| S-13 | `updatesFieldsAndKeepsCreatedAt`, `blankTitleLeavesFilesUntouched`, `everyFixtureDropSurvivesAnEditAndRescan` |
| S-14 | `imageDropKeepsImageOnUpdate`, `everyFixtureDropSurvivesAnEditAndRescan` |
| S-15 | `rejectsBadAndUnknownIds`, `deleteValidatesId`, `blankIdsAreInvalid` |
| S-16 | `deleteRemovesDropFromScan`, `failedMoveLeavesDropAndReportsDeleteFailed`, 앱 `LibraryModelTests.failedDeleteKeepsTheDropAndReports` + 수동(아래) |
| S-17 | `storageRootChangeIsRespected`, 앱 `scanAndSaveUseTheFolderThatSettingsPointsAt`, `choosingAFolderSavesItKeepsOtherFieldsAndReloads` |
| S-18 | `unreadableNoteKeepsDropWithWarning`, `missingContentKeepsDropWithWarning`, `missingImageKeepsDropWithWarning` |
| S-19 | `missingDropsFolderIsEmpty`, `aDropsEntryThatIsNotAFolderIsUnreadable`, `anUnlistableDropsFolderIsUnreadable`, `savesTextDropInContractFormat`(`drops/` 생성) |
| S-20 | `minimalImageDropDefaultsToImagePng`, `everyFixtureScansAsTheReadmeExpects` |
| C-01 | `theSettingsFileLivesInApplicationSupportWhateverTheStorageFolderIs` |
| C-02 | `missingFileCreatesDefaults`, `brokenAndIncompleteFilesAreInvalid`, `readsFullFixture` |
| C-03 | `partialUpdateKeepsOtherFieldsAndBumpsTimestamp`, 앱 `changingCaptureModePersistsAndKeepsTheme`, `changingThemePersistsAndKeepsOtherFields` |
| C-04 | `legacyFixtureFillsDefaultsAndFixesTheme`(키 없음 → `modal`), `brokenAndIncompleteFilesAreInvalid`(잘못된 값 → `settings_invalid`). 갱신 API는 열거형이라 잘못된 값을 만들 수 없다. |
| C-05 | `clampFixtureNormalizes`, `clampsPaneWidthsAndNormalizesRecentTags` |
| C-06 | 저장소 부분만: `rejectsUnparseableShortcutWithoutWriting`(파일 그대로), `ShortcutTests`. ☐ 유지(아래). |
| C-07 | `aFailedWriteKeepsTheOldFileAndLeavesNoTempFile`, `writtenFileUsesContractKeysAndLeavesNoTempFiles`, `concurrentUpdatesAreSerialized` |
| C-08 | 단위: `ShortcutControllerTests`, `ShortcutModelTests`. ☐ 유지(아래). |
| C-09 | `ShortcutControllerTests.startupRegistersOnlyTheStoredShortcut` |
| C-10 | 앱 `colorSchemeFollowsTheme`, `changingThemePersistsAndKeepsOtherFields` |
| C-11 | `legacyFixtureFillsDefaultsAndFixesTheme`(`sepia` → `system`), `clampFixtureNormalizes`(공백 경로 → 기본 폴더) |
| C-12 | 수동(STA-63 기록) |

### 고친 결함 (레거시와 다르던 곳)

- `imagePath`가 없는 레거시 이미지 Drop을 수정하면 `drop.json`에 `"imagePath": null`을 썼다. 읽을 때는 `image.png`로 보므로
  화면은 정상이었지만 S-01·스펙 1.2(이미지 Drop은 `"image.png"`)와 어긋났다. 레거시처럼 `image.png`를 기록한다.
- 스캔이 심볼릭 링크로 된 Drop 폴더를 건너뛰었다. 레거시 `is_dir`와 Swift의 수정·삭제 경로(`existingFolder`)는 링크를 따라가므로
  목록에만 빠져 있었다. 스캔도 링크를 따라간다.
- 공백뿐인 Drop ID가 `drop_not_found`였다. 레거시처럼 `invalid_drop_id`다(S-15 "비면").
- slug가 ASCII 여부를 소문자 변환 **전에** 판정해, 소문자가 ASCII인 문자(켈빈 기호 `K` → `k`)를 버렸다. 레거시처럼 먼저 소문자로
  바꾼 뒤 걸러낸다. 새 Drop ID에만 영향이 있고 기존 폴더 읽기와는 무관하다.

### 레거시와 다르지만 그대로 둔 것

- `drop.json` 서식: Swift `JSONEncoder`는 키를 알파벳 순으로 쓰고 `"key" : value`(콜론 앞 공백)로 쓴다. 레거시는 구조체 순서와
  `"key": value`다. 들여쓰기 2칸, 키 집합, `null` 규칙, 이스케이프하지 않은 `/`와 한글은 같고 JSON으로는 동일하다. 레거시 앱도
  그대로 읽는다. 맞추려면 직렬화기를 직접 써야 해서 바꾸지 않았다.
- 시각: `Date`의 정밀도가 마이크로초라 새 시각의 소수 9자리 중 끝 3자리는 항상 `000`이다. 자리 수는 9자리로 같아 정렬은 맞다.
- `content.md`나 이미지 파일이 **없을** 때 Swift는 `drop_content_unreadable`/`drop_image_unreadable` 경고를 남긴다. 레거시는
  파일이 있는데 읽지 못할 때만 경고했다. 사용자에게 알리는 편이 낫다고 보고 유지한다(`missingContentKeepsDropWithWarning`).
- 이미지 경로가 폴더 밖(`..`, 절대 경로)을 가리키면 읽지 않고 경고한다(`unsafeImagePathIsNotFollowed`). 레거시는 그대로 따라갔다.

### 수동 확인 (2026-10-12)

- 실제 레거시 폴더: `~/Documents/plopcut`을 임시 위치로 복사하고, `PLOPCUT_COMPAT_FOLDER=<복사본> swift test --filter
  RealFolderCopyTests`로 확인했다. 테스트는 그 복사본을 다시 복사해서 쓴다. Drop 7개(모두 텍스트, 전체 키, 9자리 시각)가 경고 없이 읽혔고,
  모두 수정한 뒤 다시 스캔해도 ID 순서·제목·태그·노트·본문·출처·`createdAt`이 같았고 `drop.json`은 계약 키 집합이었다. 원본은
  `diff -rq`로 바뀌지 않았음을 확인했다. 이 폴더에는 이미지 Drop이 없어 이미지는 픽스처로만 확인했다.
- S-16: 픽스처 Drop 폴더의 임시 복사본을 `FileManager.trashItem`(`SystemTrashMover`와 같은 API)으로 옮기면 원래 위치에서 사라지고
  `~/.Trash`에 생겼다(확인 뒤 휴지통에서 그 항목만 지움). 실패 경로는 주입 테스트로만 확인했다.

### 남은 항목

- C-06, C-08: 저장소·설정 파일 쪽 동작(파싱 불가면 거부하고 파일 그대로, 등록→해제→저장 순서와 롤백)은 단위 테스트로 확인했다.
  남은 것은 STA-69·STA-70의 실제 키 녹화와 전역 단축키 수동 확인 10단계(위 "단축키 키 녹화와 저장 전 미적용 기록")라 사람이
  실제 앱에서 해야 한다. 그때까지 ☐로 둔다.
- 실제 앱 화면에서 복사본 폴더를 열어 보는 확인(위 "호환성 검증 절차" 2~4단계)은 이번에 하지 않았다. 같은 스캔·수정 경로를 테스트로
  확인했다.

## 권한 누락과 오류 UX 점검 (STA-78)

점검 결과: 오류 7종(선택 텍스트 없음, 클립보드 비어 있음, 복원 실패, 저장 폴더 문제, 이미지 쓰기 실패, 메타데이터 실패, 권한 누락)은 이미 코드별 지역화 문구가 있었다. 빠진 것은 (1) 문구 없이 `defaultError`로 떨어지던 코드(`settings_*`, `delete_failed`, `drop_not_found`, `invalid_drop_id`, `export_failed`, `save_failed`)와 (2) 오류 알림의 다음 행동이었다.

- 문구 추가(en/ko, `strings.md`와 `StringTable.swift`): `settingsFailure`, `deleteFailed`, `dropNotFound`, `exportFailed`. `storageFailure`에 "설정에서 다른 폴더를 선택하세요" 안내를 더했다.
- 다음 행동: 메인 창 오류 알림에 `permission_missing`이면 `시스템 설정 열기`(손쉬운 사용 화면), 저장 폴더·설정 오류면 `설정 열기`(Settings 화면) 버튼을 붙였다(`ErrorRecovery`, `LibraryModel.performRecovery`). 손쉬운 사용 URL은 `PermissionsModel.accessibilitySettingsURL` 하나를 쓴다.
- 메타데이터 실패(M-02, M-03)는 경고라 저장을 막지 않고, 저장소 실패는 저장을 막고 이유를 보인다. 기존 동작 그대로이며 `SelectedTextCaptureTests.sourceFailureNeverBlocksCapture`, `StorageFolderCheckTests`가 확인한다.
- 단위: `LocalizationTests`(새 코드 8개의 문구, `recoverableErrorsOfferAButton`), `LibraryModelTests`(권한 알림 → 손쉬운 사용 URL, 저장 폴더 알림 → Settings, 복구 버튼이 없는 알림과 닫을 때 정리). A-04는 이 단위 테스트와 기존 `PermissionsModelTests`로도 확인한다.
- 범위 밖: 저장 폴더 검증 자체는 STA-60. 저장 팝업 안의 저장 실패 문구에는 버튼을 붙이지 않았다(문구만 보인다).

수동 확인이 남음(실제 앱, 헤드리스 불가): 손쉬운 사용을 끈 채 `Shift+Cmd+C` 시 알림 문구와 `시스템 설정 열기` 버튼이 손쉬운 사용 화면으로 가는지, 허용 후 앱으로 돌아오면 설정 화면의 상태가 갱신되는지, 허용을 거부·취소한 뒤 다시 허용, 앱 업데이트(서명 변경) 후 권한이 초기화됐을 때의 안내, Chrome 자동화 거부 상태에서 저장이 막히지 않는지, 저장 폴더를 읽기 전용으로 바꾼 뒤 캡처·편집·삭제 때 알림과 `설정 열기` 버튼, 이미지 쓰기 실패 문구, 한국어·영어 시스템 언어에서 각 문구.

## 로컬 로그 (STA-80)

앱에 로그가 없었다. `~/Library/Logs/plopcut/plopcut.log`에 시각이 붙은 한 줄씩 덧붙인다. 외부 전송 없음(spec 제품 경계: 텔레메트리 없음).

- 구현: `PlopcutCore/EventLog.swift`(`EventLogging` 프로토콜, `FileEventLog`, `LogEvent`), 앱의 `AppLog`. 1MB에 이르면 `plopcut.log.1`로 넘기고 새 파일을 시작한다(이전 파일 1개만 유지). 잠금으로 스레드 안전하며 쓰기 실패는 조용히 무시한다.
- 기록: 앱 시작(버전·빌드·macOS 버전), 화면에 표시된 오류의 코드(알림창뿐 아니라 STA-84: Library 노트·제목·태그 자동 저장 실패 `DropEditor`, 저장 팝업의 저장 실패 `SavePopupModel`. 자동 저장은 실패로 바뀔 때 한 번만 기록하고 `다시 시도`가 계속 실패해도 다시 쓰지 않으며, 다른 Drop으로 옮겨 알림창이 뜨는 경우는 이중 기록하지 않는다), 권한 상태 변경(바뀔 때만). `LogEvent`가 고정된 형태만 받고 문자열은 `[A-Za-z0-9._-]` 40자 이하만 통과(아니면 `invalid`), `PlopcutError.detail`은 읽지 않는다. 드롭 내용·노트·제목·태그·URL·클립보드·경로는 기록하지 않는다.
- UI: Settings 정보 구역에 `Finder에서 로그 보기`(`showLogInFinder`, en/ko). 로그가 없으면 폴더를 연다.
- 문서: README.md, README.ko.md, `docs/privacy.md`에 위치·내용·로컬 보관·신고 방법(사용자가 직접 첨부)을 적었다.
- 단위: `EventLogTests`(덧붙이기와 시각, 회전, 쓰기 실패 무시, 동시 쓰기, 민감 문구가 코드만 남는지), `DropEditorTests`·`SavePopupModelTests`(주입한 `EventLogging`에 코드 한 줄만, 내용·경로 없음), `LoggingTests`(권한 변경 한 번만 기록, 시작 줄, 문구, 테스트가 실제 로그에 쓰지 않음).

수동 확인이 남음(실제 앱): `Finder에서 로그 보기`가 파일을 선택해 Finder를 여는지(로그가 없을 때는 폴더), 처음 실행 후 시작 줄이 생기는지, 손쉬운 사용을 끄고 캡처했을 때 `permission_missing` 줄이 생기고 문구·경로가 없는지, 설정에서 권한을 바꾼 뒤 돌아왔을 때 권한 변경 줄, 로그 폴더를 읽기 전용으로 만들어도 앱이 정상 동작하는지, 1MB를 넘긴 뒤 `.1` 파일 생성, 한국어·영어 시스템 언어의 단추 문구.

## PLO-96: 말줄임표 제거, 메뉴 막대 클릭, 저장 시 포커스

- 문구: 메뉴 항목, 플레이스홀더, 진행 상태 문구에서 `...`/`…`를 지웠다(`Save Clipboard`, `클립보드 저장`, `저장 중` 등). 단위: `LocalizationTests.noPhraseUsesAnEllipsis`.
- 메뉴 막대(T-01): 상태 항목에 메뉴를 늘 붙여 두고 열 때마다 `menuNeedsUpdate`에서 다시 만든다. 좌클릭·우클릭 모두 메뉴를 열고 앱을 활성화하지 않는다.
- Save Popup: `.nonactivatingPanel`로 만들고 `NSApp.activate`를 뺐다. 팝업이 키보드를 받지만 plopcut은 활성화되지 않아 메인 창이 앞으로 오지 않고, 저장·취소 뒤 사용자가 쓰던 앱에 포커스가 남는다. 단위: `SavePopupWindowTests.Layout.thePopupDoesNotActivateTheApp`.
- Save Popup 키: plopcut이 비활성이면 AppKit이 단축키(key equivalent)를 앱에 주지 않아 `Cmd+Enter`, Escape, 편집 메뉴(`Cmd+V` 등)가 듣지 않았다. `SavePopupPanel.sendEvent`가 처리되지 않은 명령 키와 Escape를 창의 단추 단축키로, 그다음 편집 명령(잘라내기, 복사, 붙여넣기, 전체 선택, 실행 취소, 실행 복귀)으로 보낸다. 한국어 자판처럼 라틴 문자가 없는 자판은 키 위치로 판단한다. 단위: `SavePopupWindowTests.KeyRouting`, `NoteEditor.editShortcutsReachTheNoteWithoutTheEditMenu`.
- 실패(P-13, T-04): 선택 텍스트 캡처 실패도 메뉴 막대 실패 표시와 오류 보관만 한다. `permission_missing`만 예외로 메인 창을 연다(소유자 결정).

## PLO-102: Drop 고정과 아이콘 동작 버튼

- 저장 형식: `drop.json`에 `pinnedAt`을 항상 쓴다. 픽스처 `image-drop`은 고정, `example-app`은 `null`, 나머지는 키 없음. 단위: `PinTests.DropStorePinTests`(왕복, `updatedAt` 유지, 다시 고정해도 처음 시각, 고정한 상태로 저장, 예전 폴더), `CompatibilityTests`(계약 키).
- 목록: `ListSection.make`가 `고정됨` 묶음을 날짜 그룹 앞에 둔다. 단위: `PinTests.ListSectionTests`. 선택 대체 규칙의 "첫 항목"은 화면의 첫 행(고정됨 포함).
- 앱: `SidebarSelection.pinned`, `LibraryModel.togglePin`, `PinCommand`(`⇧⌘P`), 우클릭 메뉴 맨 위 고정/고정 해제와 단축키 표시, 동작 버튼 `DropAction`. 단위: `PinModelTests`, `PinPresentationTests`(툴팁 `이름 (단축키)`, 행 접근성 `고정됨`).
- 실제 앱(픽스처 복사본, 라이트, 1120×720): 사이드바 `고정됨 1`, 목록 맨 위 `고정됨` 묶음과 파란 핀, 첫 행 선택, 동작 버튼 38×26 pt(스크린샷에서 측정), 고정 버튼 눌린 상태, 휴지통 빨강·구분선 뒤를 확인했다.
- 수동 확인이 남음: 고정됨 Collection 클릭(묶음 제목 없음), 동작 버튼·우클릭 메뉴·`⇧⌘P`로 고정·고정 해제 클릭 흐름, 툴팁 표시, VoiceOver 낭독, 다크 모드, 시안(MainFeatures, FeatureDetails 3번)과 나란히 비교. 그래서 S-21~S-23, L-21은 단위로 ☑, L-22~L-25는 ☐로 둔다(PLO-103이 L-16~L-20을 먼저 써서 번호를 옮겼다).

## PLO-101: 본문 렌더링과 형식 메뉴

- 저장: `drop.json`에 `format`·`codeLanguage`를 더했다(R-01, R-02). 단위: `DropFormatStorageTests`(왕복, 지우기, `updatedAt`·`content.md` 유지, 예전 파일, 모르는 값), 픽스처 `storage-format`. 고정(`pinnedAt`, PLO-102)과 같은 `drop.json`에 함께 쓴다.
- 감지: `FormatDetection`(PlopcutCore). 단위: `FormatDetectionTests`(R-03).
- 렌더링: `BodyRenderer`(swift-markdown 0.9.0)가 Sendable 블록으로 바꾸고, `RenderedBodyView`가 그린다. 하이라이팅은 HighlighterSwift 3.1.0, 테마 `github`/`github-dark`. 단위: `BodyRendererTests`(R-04, R-07), `CodeHighlighterTests`, `FormatMenuTests`(이름, 체크, 코드 복사), `DropFormatModelTests`(형식 저장·다시 읽기·지우기·실패, 링크 스킴), `SavePopupModelTests.previewUsesTheDetectedFormat`.
- 앱 묶음: `scripts/make-app.sh`가 의존성의 SwiftPM 리소스 묶음(`Highlighter_Highlighter.bundle`)을 `Contents/Resources`에 복사한다. 없으면 하이라이터가 시작할 때 앱이 멈춘다.
- 실행 확인(2026-10-18, 다크, `storage-format` 복사본): 형식 버튼 `Python ▾`, 코드 블록의 언어 이름·복사 버튼·`github-dark` 색이 보였다.

수동 확인이 남음: 라이트 모드 색, Markdown 요소 모양과 시안(MainFeatures, FeatureDetails 2번) 비교, 형식 메뉴 선택과 재실행 후 유지, 텍스트 선택·복사, 링크가 기본 브라우저로 열리는지, Save Popup 미리보기와 배지, VoiceOver(R-06, R-09, R-10).
