# 앱 아이콘 출처 (STA-72)

`NotedropApp/Resources/AppIcon.icns`는 레거시 Tauri 앱의 `src-tauri/icons/icon.icns`를 그대로 복사한 파일이다(98,451 바이트).
저장소 어디에도 Notedrop 전용으로 그린 로고가 없었고, 이 아이콘은 Tauri 기본 템플릿 그림으로 보인다.

- 쓰임: `scripts/make-app.sh`가 이 파일을 앱 번들의 `Contents/Resources`로 복사하고 `Info.plist`에 `CFBundleIconFile=AppIcon`을 쓴다. Dock 아이콘과 Library 빈 상태 화면의 로고가 이 파일을 쓴다.
- 교체: 정식 로고가 생기면 같은 이름으로 파일만 바꾸면 된다. 코드 변경은 필요 없다.
- 번들 밖 실행(`swift run`)에서는 번들 리소스가 없어 `NSApp.applicationIconImage`를 쓴다.
- 확인 필요: 라이트와 다크 테마에서 빈 Library 화면의 로고가 잘 보이는지(투명 배경 아이콘이면 다크에서 대비가 약할 수 있다).
