# MandalaThink

[English](../README.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · 한국어

MandalaThink는 iPhone과 iPad에서 쓰는 아홉 칸 사고 도구입니다. 3×3 보기에서 한 가지 주제를 정리하고 9×9 보기에서 다음 단계의 내용을 한눈에 볼 수 있습니다. 각 칸에는 메모, 사진, 첨부 파일, 할 일을 넣고 색상으로 표시할 수 있습니다. 한국어, 영어, 중국어 간체, 일본어를 지원합니다.

## 만다라 사고법

3×3 격자의 중앙에 질문이나 목표를 쓰고, 주변 여덟 칸에 관련 아이디어를 적습니다. 더 살펴보고 싶은 아이디어가 있으면 새 격자의 중앙에 놓습니다. 예를 들어 ‘발표 준비’의 주변에 ‘청중’, ‘자료’, ‘시간’을 적고, ‘자료’를 펼쳐 사례와 이미지, 참고 문헌을 정리할 수 있습니다. [MandalArt 소개](https://www.atpress.ne.jp/news/11958)

## 사용 방법

1. **프로젝트를 만들거나 엽니다.** ‘새로 만들기’에서 프로젝트 이름과 중심 주제를 입력합니다. ‘열기’에서 편집용 `.mprj`를 열거나 공유용 `.mandalaprj`와 이전 형식인 `.mandala`를 가져올 수 있습니다.
2. **칸을 편집하고 펼칩니다.** 빈 칸을 눌러 입력하면 자동으로 저장됩니다. 첫 번째 비어 있지 않은 줄이 미리보기에 표시됩니다. 내용이 있는 칸을 누르면 상세 화면이 열리고, 오른쪽 위 버튼을 누르면 다음 단계로 이동합니다.
3. **보기를 전환합니다.** 보드 상단에서 3×3과 9×9를 전환합니다. 9×9에서는 전체 보드가 먼저 표시됩니다. 두 손가락으로 확대하고 드래그로 이동하며, 전체 보기 버튼으로 원래 크기로 돌아갑니다.
4. **미디어와 할 일을 추가합니다.** 편집 화면에서 사진 보관함, 카메라 또는 파일을 사용할 수 있습니다. 칸 상세 화면에서 할 일을 Apple 미리 알림에 보내고, 미리 알림의 출처 링크를 눌러 프로젝트로 돌아올 수 있습니다.
5. **공유하거나 백업합니다.** 보드 메뉴에서 `.mandalaprj` 또는 이전 형식인 `.mandala`로 내보냅니다. 패키지 구조는 [파일 형식 명세](mandala-format-v1.md)를 참고하세요.

### 브라우저 리더

`mandala-web-reader`를 실행하고 [http://127.0.0.1:8080](http://127.0.0.1:8080)을 엽니다. 이전 형식의 `.mandala` 파일을 선택하거나 페이지에 끌어 놓습니다. [sample.mandala](../MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala)로 시험해 볼 수 있습니다. 파일은 브라우저에서 읽습니다. 다른 포트를 쓰려면 `-listen 127.0.0.1:8081`을 지정하세요.

## 빌드 및 테스트

### iPhone 및 iPad

Xcode에서 저장소 루트의 [mandala-think.xcodeproj](../mandala-think.xcodeproj)를 엽니다. `mandala-think` 스킴과 iPhone 또는 iPad 시뮬레이터를 선택하고 Run을 실행합니다. iOS 또는 iPadOS 17 이상이 필요합니다. 실제 기기에서 실행하려면 **Signing & Capabilities**에서 개발 팀을 선택하세요. 기본 번들 ID는 `org.mandalathink.app`입니다.

저장소 루트에서 파일 형식 테스트를 실행합니다.

```sh
swift test --package-path MandalaCore
```

UI 테스트는 Xcode의 **Product → Test**에서 실행합니다. 이전 형식 가져오기 테스트는 기기의 앱 Documents 폴더에 `sample.mandala`를 넣고 `TEST_RUNNER_MANDALA_TEST_LEGACY_FIXTURE=1`을 설정한 뒤 `xcodebuild test`를 실행합니다. 사진 테스트는 `simctl addmedia`로 이미지를 추가하고 `TEST_RUNNER_MANDALA_TEST_PHOTO_FIXTURE=1`을 설정합니다.

### 브라우저 리더

Go 1.22 이상으로 저장소 루트에서 다음 명령을 실행합니다.

```sh
go -C apps/web-reader build -buildvcs=false -o ../../mandala-web-reader .
```

[apps/web-reader/dist](../apps/web-reader/dist)의 HTML, CSS, JavaScript가 실행 파일에 내장됩니다. 실행 파일만 복사해서 실행할 수 있습니다.
