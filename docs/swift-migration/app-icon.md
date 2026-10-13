# 앱 아이콘 출처 (STA-72)

`PlopcutApp/Resources/AppIcon.svg`가 원본 디자인이고, `AppIcon.icns`는 이 SVG를 16~512 px(@2x 포함)로 렌더링해 `iconutil`로 만든 파일이다.
디자인은 어두운 둥근 사각형 배경에 하늘색-보라 글로우 화살표가 트레이로 떨어지는 모양(Drop 컨셉)이다. 이전에는 레거시 Tauri 기본 `icon.icns`를 복사해 썼다.

- 쓰임: `scripts/make-app.sh`가 `AppIcon.icns`를 앱 번들의 `Contents/Resources`로 복사하고 `Info.plist`에 `CFBundleIconFile=AppIcon`을 쓴다. Dock 아이콘과 Library 빈 상태 화면의 로고가 이 파일을 쓴다.
- 다시 만들기: SVG를 고친 뒤 크기별 PNG로 렌더링해 `AppIcon.iconset`을 만들고 `iconutil -c icns AppIcon.iconset -o AppIcon.icns`로 교체한다. 코드 변경은 필요 없다.
- 번들 밖 실행(`swift run`)에서는 번들 리소스가 없어 `NSApp.applicationIconImage`를 쓴다.
- 확인 필요: 라이트와 다크 테마의 빈 Library 화면에서 대비가 괜찮은지.
