# 타입펫 (TypePet)

> A tiny macOS menu-bar desktop pet that animates every time you type.

**타입펫**은 키보드를 누를 때마다 화면 위의 캐릭터가 움직이는 macOS 메뉴 막대 앱입니다. 평소에는 쉬는 동작을 하다가, 타이핑하면 입을 벌리고 손을 흔들고, 빨리 치면 더 크게 움직이고, 엔터와 지우기에는 각각 다른 동작을 합니다. 그림 파일을 넣어 나만의 캐릭터로 바꿀 수도 있습니다.

## 주요 기능

- **키 입력 반응** — `CGEvent` 탭으로 키가 눌렸는지만 감지합니다. 입력한 글자는 읽거나 저장하지 않고, 엔터/지우기 여부와 눌린 횟수만 씁니다.
- **5가지 동작** — 타이핑(`type`), 빠른 타이핑(`fast`), 엔터(`enter`), 지우기(`back`), 쉬기(`rest`).
- **기본 캐릭터 내장** — `generate.swift`가 빌드할 때 기본 캐릭터 프레임과 앱 아이콘 원본을 코드로 그려 생성합니다.
- **나만의 캐릭터** — 이미지(png, jpg, gif, webp, heic 등)를 캐릭터 위로 끌어다 놓거나 조절 창에서 추가합니다. 여러 캐릭터를 두고 메뉴에서 바꿀 수 있습니다.
- **조절 창** — 크기, 쉬는 타이밍을 슬라이더로 바꾸고 동작별 그림을 관리합니다.
- **메뉴 막대 옵션** — 캐릭터 숨기기/보이기, 항상 맨 위에 보이기, 위치 고정(클릭이 뒤로 통과), 로그인할 때 자동 실행.
- **자동 업데이트** — GitHub Releases의 최신 버전을 확인해 zip을 받아 교체합니다.

### 캐릭터 그림 파일 이름 규칙

```
type_00.png   키를 누를 때마다 (이어서 type_01, type_02 …)
fast_00.png   빨리 칠 때
enter_00.png  엔터
back_00.png   지우기
rest_00.png   쉴 때
```

이름 규칙이 없으면 폴더 안 이미지가 모두 타이핑 동작이 됩니다. 캐릭터 폴더는 `~/Library/Application Support/TypePet/packs` 아래에 있습니다.

## 기술 스택

- Swift (단일 `swiftc` 빌드, Xcode 프로젝트 없음)
- AppKit, CoreGraphics(`CGEvent` 키 이벤트 탭), QuartzCore, ImageIO
- ServiceManagement(`SMAppService`)로 로그인 시 자동 실행
- 대상: macOS 13 이상, Apple Silicon(arm64)

## 설치

[Releases](https://github.com/dong3789/TypePet/releases)에서 `TypePet.zip`을 받아 압축을 풀고 `TypePet.app`을 `/Applications`로 옮깁니다.

처음 실행하면 **시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링**에서 타입펫을 허용해야 키 입력에 반응합니다.

## 직접 빌드

Xcode Command Line Tools가 설치된 macOS에서:

```bash
./build.sh
```

`build.sh`는 다음을 수행합니다.

1. `generate.swift`로 기본 캐릭터 프레임과 아이콘 원본 생성 (`Resources/`)
2. `sips` / `iconutil`로 `AppIcon.icns` 생성
3. `swiftc`로 `src/*.swift` 컴파일 → `build/TypePet.app` 패키징 및 서명
4. 기본값으로 `/Applications/TypePet.app`에 설치 (`TYPEPET_INSTALL=0`이면 설치 생략)

릴리스는 `./release.sh <버전> "릴리스 노트"`로 빌드 → 태그 → GitHub Release 업로드를 한 번에 합니다.

## 프로젝트 구조

```
src/
├── TypePet.swift   # 앱 본체: 키 모니터, 캐릭터 창/애니메이션, 메뉴 막대, 캐릭터 가져오기
├── Editor.swift    # ‘조절’ 창: 크기·쉬는 타이밍, 동작별 그림 관리
└── Updater.swift   # GitHub Releases 기반 업데이트 확인·설치
generate.swift      # 기본 캐릭터 프레임 · 아이콘 생성 스크립트
build.sh            # 빌드 · 서명 · 설치
release.sh          # 버전 올리기 · 릴리스
Info.plist          # 번들 설정 (메뉴 막대 전용 앱, 입력 모니터링 사용 설명)
VERSION             # 현재 버전
```
