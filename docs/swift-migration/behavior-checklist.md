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
| S-16 | 삭제는 폴더 전체를 휴지통으로 이동. 이동 후에도 폴더가 있으면 `delete_failed`이고 목록에 남는다. | 테스트: `delete_helper_removes_drop_from_scan_when_trash_mover_succeeds`, `delete_helper_leaves_drop_when_trash_mover_fails` | 단위(이동 동작 주입) + 수동 | ☐ |
| S-17 | 저장 폴더 설정을 바꾸면 스캔과 저장이 새 폴더를 쓴다. | 테스트: `save_and_scan_use_configured_storage_root` | 단위 | ☑ |
| S-18 | 읽는 중 `content.md`/이미지/`note.md` 하나가 실패해도 Drop은 남기고 해당 경고만 추가. | `read_drop_folder` | 단위 | ☑ |
| S-19 | `drops/`가 없으면 빈 목록(오류 아님). 저장 시에는 `drops/`를 만든다. | `scan_drops_from_root` | 단위 | ☑ |
| S-20 | 이미지 Drop은 `imagePath`가 없어도 `image.png`를 기본으로 본다. | `read_drop_folder` | 픽스처: `legacy-minimal-image` | ☑ |

## C. 설정

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| C-01 | 설정 파일 경로는 고정(`~/Library/Application Support/Notedrop/settings.json`)이고 저장 폴더 설정과 무관. | `settings.rs` | 단위 | ☐ |
| C-02 | 파일이 없으면 기본값을 만들어 저장. JSON이 깨지면 `settings_invalid`. | 테스트: `default_settings_use_default_storage_and_system_theme` | 단위·픽스처 | ☑ |
| C-03 | 부분 갱신: 보낸 필드만 바꾸고 나머지는 유지, `updatedAt` 갱신. | 테스트: `updating_settings_persists_path_first_run_theme_and_updated_at`, `updating_settings_persists_shortcuts_without_changing_unrelated_fields` | 단위 | ☑ |
| C-04 | `captureConfirmationMode` 키가 없으면 `modal`. 잘못된 값으로 갱신하면 거부. | 테스트: `missing_capture_confirmation_mode_defaults_to_modal`, `update_rejects_invalid_capture_confirmation_mode` | 단위 | ☐ |
| C-05 | `paneWidths`는 읽고 쓸 때 180–320 / 300–560으로 고정, `recentTags`는 태그 규칙과 12개 제한. | 테스트: `updating_settings_persists_pane_widths_and_recent_tags` | 단위 | ☑ |
| C-06 | 단축키 문자열은 Tauri 문법(`Shift+Cmd+K`)으로 저장. Swift가 이 문자열을 파싱해야 하며 파싱 불가면 저장 거부. 파일은 바뀌지 않아야 한다. | 테스트: `update_rejects_unparseable_selected_text_shortcut`, `update_rejecting_invalid_shortcut_leaves_persisted_settings_file_untouched` | 단위: 수식어(`Shift`, `Cmd`/`Command`, `Ctrl`/`Control`, `Alt`/`Option`)와 키 이름 | ☑ |
| C-07 | 원자적 쓰기(임시 파일 + 이름 변경)로 쓰고 쓰기 실패 시 임시 파일을 지운다. 동시 갱신은 직렬화. | `atomic_write_settings`, `SETTINGS_UPDATE_LOCK` | 단위 | ☐ |
| C-08 | 단축키 변경 순서: 새 것 등록 → 이전 것 해제 → 설정 저장. 어느 단계가 실패해도 이전 단축키가 살아 있어야 한다. | 테스트: `changing_selected_text_shortcut_replaces_the_old_registration`, `failed_registration_keeps_the_previous_shortcut_active`, `persistence_failure_restores_the_previous_shortcut` | 단위(가짜 등록기) + 수동 | ☐ |
| C-09 | 시작 시 저장된 단축키 하나만 등록(다른 단축키는 등록하지 않음). 등록 실패는 보관 오류와 메뉴 막대 `Error`로 알린다. | 테스트: `startup_registers_only_the_selected_text_shortcut` | 수동 | ☐ |
| C-10 | `theme`가 `system`이면 앱 외형을 시스템에 맡기고, `light`/`dark`는 시스템을 덮어쓴다. | `useTheme.ts` | 수동 | ☐ |
| C-11 | 읽은 `theme`이 잘못되면 `system`으로 보정, `storageFolderPath`가 공백이면 기본 폴더. | `read_app_settings_from_path` | 단위 | ☑ |
| C-12 | 번들 ID를 바꾸면 손쉬운 사용·자동화 권한을 새로 허용해야 한다. 설정과 Drop은 영향이 없다. | — | 수동 | ☐ |

## P. 캡처 (선택 텍스트)

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| P-01 | 출처 수집이 클립보드 백업·복사보다 **먼저**. | 테스트: `selected_text_capture_collects_source_first_and_restores_text_and_image` | 단위(호출 순서) | ☐ |
| P-02 | 복사 후 대기: 변경 횟수가 달라질 때까지 25 ms 폴링, 최대 700 ms. | `SELECTED_TEXT_COPY_TIMEOUT`, `POLL_INTERVAL` | 단위·수동 | ☐ |
| P-03 | 복사한 텍스트가 이전 클립보드와 같아도 변경 횟수가 달라졌으면 성공. | 테스트: `selected_text_capture_accepts_text_that_matches_the_previous_clipboard` | 단위 | ☐ |
| P-04 | 시간 초과, 빈 선택, 읽기 실패, 복사 시뮬레이션 실패 **모두에서** 이전 클립보드를 복원한다. | 테스트: `selected_text_capture_restores_clipboard_after_copy_timeout`, `…_after_empty_selection`, `…_after_read_failure`, `…_when_copy_shortcut_fails` | 단위 | ☐ |
| P-05 | 복원 실패는 캡처 실패가 아니라 경고(`clipboard_restore_failed`)가 붙은 성공. | 테스트: `selected_text_is_returned_with_a_warning_when_restore_fails` | 단위 | ☐ |
| P-06 | 백업이 실패해도(경고 `clipboard_backup_failed`) 캡처는 계속하고 복원을 시도한다. | 테스트: `selected_text_capture_attempts_restore_when_backup_fails` | 단위 | ☐ |
| P-07 | 선택된 텍스트가 없으면 `no_selected_text`(공백뿐인 텍스트 포함). 끝의 `\r`/`\n`은 제거. | `trimmed_capture_text` | 단위 | ☐ |
| P-08 | 자동화·접근성 오류는 `permission_missing`으로 바꾸고 손쉬운 사용 권한 안내를 붙인다. | `capture_selected_text_with` | 수동: 권한 없이 실행 | ☐ |
| P-09 | 백업 대상은 텍스트와 PNG 이미지. 이미지는 PNG로 정규화해 보관·복원한다. 복원은 텍스트와 이미지를 한 항목으로 쓴다. | `write_clipboard_snapshot` | 수동: 이미지만/텍스트만/둘 다 있던 클립보드 | ☐ |
| P-10 | 결과 Draft는 `note` 없음, `tags` 빈 배열. | `capture_selected_text_with` | 단위 | ☐ |
| P-11 | `modal`이면 팝업, `instant`이면 텍스트만 즉시 저장(노트 `""`, 태그 없음). | `instant_save_payload_from_draft`, `handle_capture_draft` | 테스트: `instant_save_payload_uses_empty_note_and_tags` | ☐ |
| P-12 | `instant`에서도 이미지·`mixed`는 팝업. 도구 막대 버튼 캡처는 `instant`와 무관하게 항상 팝업. | `handle_capture_draft`, `MainWindow.tsx` `captureSelectedText` | 수동 | ☐ |
| P-13 | 선택 텍스트 캡처 실패: 오류 보관 + 메인 창 표시 + 메뉴 막대 `Error`. 보관 오류는 메인 창에서 **한 번만** 소비. | `emit_selected_text_capture_event`, 테스트: `pending_capture_error_is_returned_once` | 단위·수동 | ☐ |
| P-14 | 별도 팝업 창이 이미 열려 있으면 재사용하고 새 Draft로 교체. | `open_capture_window` | 수동: 팝업을 연 채 단축키 재입력 | ☐ |
| P-15 | 레거시는 클립보드 접근을 `swift -e` 서브프로세스로 했다. Swift 앱은 `NSPasteboard`를 직접 쓰므로 이 구조는 이어받지 않는다(같은 시맨틱만 유지). | `capture.rs` | — | ☐ |

## K. 클립보드 캡처 (메뉴 막대 `Save Clipboard...`)

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| K-01 | 변경 횟수를 읽기 전후로 비교해 다르면 `clipboard_changed`. | 테스트: `clipboard_snapshot_rejects_content_changed_during_read` | 단위 | ☐ |
| K-02 | 분류: 텍스트만 `text`, 이미지만 `image`, 둘 다 `mixed`, 둘 다 없으면 `clipboard_empty`. | 테스트: `clipboard_snapshot_classifies_text_image_and_mixed_content` | 단위 | ☐ |
| K-03 | 이미지 디코딩 실패 시 텍스트가 있으면 텍스트로 진행하고 경고 `clipboard_image_unavailable`. 텍스트도 없으면 그 오류로 실패. | 테스트: `clipboard_snapshot_prefers_text_when_image_decoding_fails`, `clipboard_snapshot_rejects_unreadable_content` | 단위 | ☐ |
| K-04 | 이미지는 PNG가 있으면 PNG, 없으면 TIFF를 PNG로 변환해 사용. | `read_clipboard_snapshot` | 수동: 스크린샷(PNG)과 TIFF를 내는 앱 | ☐ |
| K-05 | 최전면 앱이 Notedrop이면 출처를 비우고 제목을 다시 추론. 다른 앱이면 출처 유지. | 테스트: `tray_capture_omits_notedrop_source_and_reinfers_title`, `tray_capture_preserves_non_notedrop_source` | 단위 | ☐ |
| K-06 | 클립보드 캡처 실패는 오류 보관 + 메뉴 막대 `Error`만(메인 창을 띄우지 않음). | `emit_tray_clipboard_capture_event` | 수동 | ☐ |

## M. 출처 수집

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| M-01 | 최전면 앱 이름과 앞 윈도우 제목. 제목을 못 얻어도 앱 이름은 유지. | `collect_source_metadata` | 수동 | ☐ |
| M-02 | 앱이 `Google Chrome`일 때만 활성 탭 URL을 시도. 실패는 경고 `chrome_url_failed`, 앱·윈도우 실패는 `metadata_failed`. | 위와 같음 | 수동: 권한 거부 상태 | ☐ |
| M-03 | 출처 수집 실패는 저장을 막지 않는다. 비어 있는 필드는 `null`로 저장. | PRD "Source metadata" | 단위 | ☐ |
| M-04 | 파일 경로는 레거시가 수집하지 않는다. 신뢰할 수 있는 API가 없으면 비워 둔다. | `collect_source_metadata` | — | ☐ |

## A. 권한

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| A-01 | 손쉬운 사용: `AXIsProcessTrusted`. 없으면 System Settings > Privacy & Security > Accessibility 안내. | `permissions.rs` | 수동 | ☐ |
| A-02 | 클립보드: 텍스트를 읽을 수 있으면 허용, 읽기 실패면 없음, 확인 불가면 알 수 없음. | `permissions.rs` | 수동 | ☐ |
| A-03 | 자동화: 항상 `알 수 없음`. Chrome이 최전면일 때만 시스템이 묻는다는 안내. `Info.plist`에 `NSAppleEventsUsageDescription` 필요. | `permissions.rs` | 수동 | ☐ |
| A-04 | 권한이 없어도 앱이 종료되지 않고 UI에 이유를 보여 준다. | PRD "macOS permissions" | 수동 | ☐ |

## L. Library

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| L-01 | 검색은 제목·본문·노트·이미지 경로·앱·윈도우·URL·태그의 부분 문자열(대소문자 무시). 이미지 경로(`image.png`)로도 검색된다. | `drop-utils.ts` `matchesDropSearch` | 단위 | ☑ |
| L-02 | 기간 필터: 오늘은 같은 달력 날짜, 7·30일은 `createdAt ≥ 지금 − N일`. 날짜를 해석할 수 없는 Drop은 기간 필터에서 제외. | `matchesDateFilter` | 단위 | ☑ |
| L-03 | 날짜 그룹: 오늘/어제/지난 7일(2~7일 전)/이전. 해석 불가한 날짜는 `이전`. 빈 그룹 숨김. | `drop-groups.ts` | 단위 | ☑ |
| L-04 | 선택이 필터 결과에서 사라지면 첫 항목, 결과가 비면 선택 없음. | `useLibraryFilters.ts` | 단위 | ☑ |
| L-05 | 사이드바 선택은 항상 하나. 유형 선택은 태그 필터를 지우고 태그 선택은 유형을 `all`로 돌린다. 필터 지우기는 앱·기간만 지운다. | `Sidebar.tsx`, `useLibraryFilters.ts`(STA-37) | 단위 | ☑ |
| L-06 | 사이드바 접힘은 Library↔Settings 전환과 창 크기 변경을 지나도 유지. 두 화면에서 사이드바 너비·모양이 같다. | `MainWindow.tsx`(STA-38) | 수동 | ☑ |
| L-07 | 인스펙터 오버레이: 같은 토글 또는 Escape로 닫고 토글로 포커스 복귀. 검색 편집 중 Escape는 검색을 먼저 닫는다. | `docs/design/sta30-font-book/README.md` | 수동 | ☐ |
| L-08 | 검색을 닫아도(Escape) 검색어와 결과 유지. 지우기는 전체 복원. `Cmd+F`는 검색 포커스. | `design-system.md` | 수동 | ☐ |
| L-09 | 새로고침은 디스크를 다시 스캔한다. 다른 곳(팝업 창 등)의 저장 신호를 받아도 다시 스캔한다. | `useLibraryRefreshEvent.ts` | 수동 | ☐ |
| L-10 | 저장한 뒤 새 Drop을 선택한다. | `handleCaptureSaved` | 수동 | ☐ |
| L-11 | 목록 우클릭 메뉴: 출처 열기(URL 있을 때), 내용 복사(텍스트일 때), Markdown 내보내기, 구분선, 휴지통. 우클릭하면 그 행을 먼저 선택. | `LibraryPane.tsx` | 수동 | ☐ |
| L-12 | `Cmd+Backspace`는 삭제 확인 시트, 확인 후에만 휴지통으로 이동. | `LibraryPane.tsx`, `DeleteConfirmationSheet.tsx` | 수동 | ☐ |
| L-13 | 출처 열기: URL이 비어 있으면 `source_url_missing`. 버튼은 URL이 없을 때 비활성. | `commands.rs` `open_source_url` | 단위·수동 | ☐ |
| L-14 | Markdown 내보내기: 취소하면 파일을 쓰지 않는다. 형식은 spec 7장. | `markdown.rs`, 테스트: `markdown_generation_includes_drop_fields` | 단위 | ☐ |
| L-15 | 창 크기 때문에 줄어든 표시 너비를 `paneWidths`에 저장하지 않는다. 구분선 조절이 끝났을 때만 저장. | `MainWindow.tsx` | 수동 | ☐ |

## E. 편집

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| E-01 | 편집 600 ms 후 자동 저장, 입력을 떠날 때 즉시 저장. | `useDropAutoSave.ts` | 단위(가짜 타이머) | ☐ |
| E-02 | 저장 중에 더 새로운 편집이 들어오거나 다른 Drop으로 이동했으면 늦게 온 응답을 반영하지 않는다(편집 내용을 덮어쓰지 않음). | `useDropAutoSave.ts` revision/dropRef | 단위 | ☐ |
| E-03 | 변경이 없으면 저장하지 않고 상태만 `saved`로 정리. | `useDropAutoSave.ts` | 단위 | ☐ |
| E-04 | 제목이 공백이면 저장하지 않고 `blankTitle` 오류. 저장 실패 상태에서는 blur가 재시도하지 않고 `다시 시도` 버튼으로만 재시도. | `useDropAutoSave.ts`, `DropDetailPane.tsx` | 단위 | ☐ |
| E-05 | 패널을 접거나 오버레이를 열고 닫아도 편집 중인 노트·태그 초안을 잃지 않는다(편집기를 다시 만들지 않는다). | `design-system.md` | 수동 | ☐ |
| E-06 | 편집 후 목록에 즉시 반영하되 선택은 유지한다. | `useDropActions.ts` | 수동 | ☐ |

## I. 입력

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| I-01 | **한글 입력기 조합 중 Enter/쉼표로 태그를 등록하지 않는다.** | `DropDetailPane.tsx` `isComposingKey`, `SavePopover.tsx` | 수동: 한글로 태그 입력 후 Enter(조합 확정 Enter는 등록 아님) | ☐ |
| I-02 | 태그 입력은 Enter 또는 쉼표로 등록, 여러 개를 쉼표로 한 번에. 이미 있는 태그는 안내(`tagAlreadyAdded`)하고 중복 추가 안 함. | `DropDetailPane.tsx` `registerTags` | 단위 | ☐ |
| I-03 | 태그 칩 삭제 후 입력창에 포커스. | `removeTag` | 수동 | ☐ |
| I-04 | 팝업 `Cmd+Enter` 저장(저장 중이면 무시), Escape 취소. 레거시는 `Cmd+Enter`에서 입력기 조합 여부를 검사하지 않는다(조합 중에도 동작). | `SavePopover.tsx` | 수동 | ☐ |
| I-05 | 포커스 링은 컨트롤 모양을 따르는 둥근 링이고 레이아웃을 밀지 않는다. 컨테이너에는 링이 없다. 목록 행은 안쪽 링. | STA-38 CSS(실제 앱 미검증) | 수동 | ☐ |
| I-06 | 제목 인라인 이름 변경: Return 확정, Escape 되돌림, 둘 다 포커스를 목록에 돌린다. | STA-38(실제 앱 미검증) | 수동 | ☐ |

## T. 메뉴 막대

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| T-01 | 템플릿 아이콘, 툴팁 `Notedrop`, 좌클릭은 메뉴가 아니라 메인 창 열기. 메뉴는 좌클릭이 아닌 방식(우클릭)으로 연다. | `tray.rs` | 수동 | ☐ |
| T-02 | 메뉴 항목 ID는 `save-clipboard`, `open-library`. 알 수 없는 ID는 무시. | 테스트: `routes_stable_tray_menu_ids`, `save_clipboard_menu_action_starts_clipboard_capture` | 단위 | ☐ |
| T-03 | 성공 `Saved`, 실패 `Error`를 900 ms 동안 제목과 툴팁에 표시하고 원복. | `show_feedback` | 수동 | ☐ |
| T-04 | 메인 창을 열 때 보관된 캡처 오류를 확인하도록 신호를 보낸다. | `show_main_window` | 수동 | ☐ |

## N. 지역화

| ID | 동작 | 근거 | 확인 방법 | ☐ |
| --- | --- | --- | --- | --- |
| N-01 | 시스템 언어가 `ko`로 시작하면 한국어, 아니면 영어. | `i18n.tsx` `resolveLocale` | 단위 | ☐ |
| N-02 | 두 언어의 키 집합이 같다(한쪽에만 있는 문구 없음). | `i18n.tsx` `Dictionary` 타입 | 단위 | ☐ |
| N-03 | 알려진 오류 코드는 지역화한 문구로, 그 밖의 코드 오류는 원본 메시지로, 문자열 오류는 그대로, 그 밖에는 `defaultError`. | `translateError` | 단위 | ☐ |
| N-04 | 권한 상세 문구는 항목×상태(허용/없음)로 키가 있고, `알 수 없음`은 `permissionUnknownDetail`. | `permissionDetail` | 단위 | ☐ |

## D. 결정이 필요한 차이와 알려진 공백

레거시에서 확인되지 않았거나 문서와 구현이 어긋난 곳입니다. 구현 전에 결정하거나 확인해 기록하세요.

| ID | 상황 | 제안 | 결정 | ☐ |
| --- | --- | --- | --- | --- |
| D-01 | PRD는 `Shift+Cmd+V`(클립보드 캡처)를 요구하지만 구현된 적이 없다. 클립보드 캡처는 메뉴 막대의 `Save Clipboard...`뿐이다. | 먼저 레거시와 같게 메뉴만 구현. 단축키는 별도 요청이 있을 때. | | ☐ |
| D-02 | 타입에 `mixed`가 있지만 **저장되는 Drop은 `text` 또는 `image`뿐**이다(`mixed` Draft는 팝업에서 하나를 고른다). 레거시는 `mixed` Drop을 목록에는 보여 주지만 본문과 이미지를 읽지 않는다(픽스처로 확인). | 최소한 레거시와 같게(깨지지 않고 목록에 표시). 본문·이미지 표시는 별도 결정. | | ☐ |
| D-03 | 레거시 단축키 문자열은 Tauri 문법이다. 전체 허용 범위(예: 방향키, 펑션키, `CmdOrCtrl`)는 문서화되어 있지 않다. | 최소 `Shift/Cmd/Ctrl/Alt` + 문자·숫자·펑션키를 지원하고 나머지는 거부. | | ☐ |
| D-04 | 이미지 Drop의 `image.png`가 아닌 다른 `imagePath`를 읽는 경로는 있으나(`drop.imagePath`) 쓰는 경로는 항상 `image.png`다. | 읽기는 `imagePath` 우선, 쓰기는 `image.png`. | | ☐ |
| D-05 | 도구 막대 `선택한 텍스트 캡처`는 Notedrop이 최전면일 때 Notedrop 안의 선택 텍스트를 캡처한다(실제로는 다른 앱의 선택을 가져오지 못한다). | 의도인지 확인. 필요하면 직전 앱으로 포커스를 돌려 캡처. | | ☐ |
| D-06 | 이름 바꾼 단축키가 다른 앱과 충돌해 등록에 실패할 때의 사용자 메시지(`shortcut_registration_failed`)가 레거시에서는 영어 원문이다. | 한국어 문구 추가. | | ☐ |
| D-07 | 메인 창을 닫았을 때 앱이 종료되는지, 메뉴 막대에 남는지가 레거시에서 확인되지 않았다. 메뉴 막대와 전역 단축키의 목적상 남는 편이 자연스럽다. | 레거시 앱으로 직접 확인한 뒤 결정. | | ☐ |
| D-08 | 로그인 시 자동 실행, Dock 아이콘 표시 여부는 정의되어 있지 않다. | 범위 밖. 필요하면 새 이슈. | | ☐ |
| D-09 | `Design.md`와 `design-system.md`의 일부 문장은 AppKit 도구 막대, `compactSearch`, `inspectorOverlay` 같은 Tauri 구현 용어를 쓴다. | Swift 구현이 안정되면 문서에서 해당 구현 용어를 제거. | | ☐ |
| D-10 | STA-38에서 도입한 SF Symbols 렌더링, 포커스 링, 제목 인라인 이름 변경, 목록 비포커스 선택 약화, 설정 화면 토글은 **실제 앱에서 확인되지 않았다.** | 레거시 앱에서 확인하지 말고 Swift 구현에서 기준(서체관리자)으로 직접 확인. | | ☐ |
| D-11 | 라이트 테마의 도구 막대와 960 pt 너비 실화면 확인이 남아 있다. | Swift 구현에서 확인. | | ☐ |
| D-12 | 문구 `shortcutFormatHint`가 "Tauri 형식"이라고 안내한다. 저장 문자열은 호환을 위해 같은 형식(`Shift+Cmd+K`)을 쓰지만 사용자에게 구현 용어를 보이면 안 된다. | 문구에서 Tauri를 빼고 형식 예시만 안내. | | ☐ |

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

미완(후속 STA-43): L-07 토글 포커스 복귀, L-08 검색 Escape·Cmd+F 실동작, L-15 구분선 조절·접근성 값(구분선은 `NavigationSplitView` 기본), 서체관리자와의 시각 차이(서체관리자는 8 pt 인셋의 떠 있는 사이드바와 도구 막대 안의 제목·개수, 캡슐로 묶인 도구 막대 버튼을 쓰지만 Notedrop은 기본 사이드바와 목록 헤더를 씁니다), Xcode 프로젝트(현재는 SwiftPM + `scripts/make-app.sh`).
