# Unity 한국어 인터페이스 / Unity Korean interface

확인일 / Verified: 2026-10-01

## 한국어

Unity Hub와 Unity Editor는 공식 한국어를 지원하므로 별도 한글 패치는 필요하지 않습니다. 이 Mac의 사용 중인 Unity 6.3 LTS 에디터에 공식 언어팩을 설치하고 한국어 표시를 확인했습니다.

### 적용 및 검증 결과

- Unity Hub `3.21.3`: `Settings > Appearance > Language`에서 한국어를 선택했습니다. 저장된 언어는 `ko_kr`입니다.
- Unity Editor `6000.3.25f1`: Hub의 모듈 추가 기능으로 공식 한국어 언어팩을 설치하고, `Languages`에서 `한국어 (Experimental)`를 선택했습니다.
- 설치 파일: `/Users/byeolee/Applications/RPG-Unity-6000.3.25f1/Unity/Unity.app/Contents/Localization/ko.po` — 2,777,994바이트.
- 게임 프로젝트와 분리한 작은 임시 프로젝트에서 에디터를 재시작한 뒤 메뉴 `파일`, `편집`, `에셋`, `게임 오브젝트`, `컴포넌트`, `서비스`, `도움말` 표시를 확인했습니다. `Window`는 영어로 남아 있습니다.
- 사용하지 않는 Unity 6.6 에디터는 이번 적용 대상에 포함하지 않았습니다.

### 다시 설정하거나 새 에디터에 적용하기

1. Hub에서 `Settings > Appearance > Language > 한국어`를 선택합니다.
2. `Installs > 해당 에디터의 Manage > Add Modules > Language packs`에서 `한국어`를 설치합니다. 한국어 모듈 ID는 `language-ko`입니다.
3. macOS 에디터에서 `Unity > Settings > Languages`를 엽니다.
4. `Editor Language (Experimental)`를 켜고 `Editor language > 한국어 (Experimental)`를 선택한 뒤 에디터를 재시작합니다.

언어팩은 에디터 설치별로 적용됩니다. 다른 버전으로 업그레이드하면 그 버전의 한국어 모듈을 설치하고 언어 선택을 확인합니다. 제공되는 모듈은 버전과 플랫폼에 따라 달라질 수 있습니다. 공식 한국어를 선택해도 일부 메뉴나 패키지 창은 영어로 표시될 수 있습니다.

이 설정은 Mac 사용자의 에디터 환경 설정이며 게임의 언어·콘텐츠 설정과는 별개입니다. 확인한 값은 `Editor.kEditorLocale = "Korean"`, `Editor.kEnableEditorLocalization = true`입니다. 컴파일러 메시지 번역 설정 `Editor.kEnableCompilerMessagesLocalization = false`는 기존 값을 유지했습니다. 공식 언어팩과 Unity 실행 파일은 로컬 설치에 보관하며 리포지터리에 포함하지 않습니다.

## English

Unity Hub and Unity Editor officially support Korean, so a custom translation patch is unnecessary. Korean was enabled for the active Unity 6.3 LTS installation on this Mac.

- Hub `3.21.3`: Korean selected in `Settings > Appearance > Language`; saved locale is `ko_kr`.
- Editor `6000.3.25f1`: official Korean module installed through Hub, then `한국어 (Experimental)` selected in Editor language settings.
- Installed file: `/Users/byeolee/Applications/RPG-Unity-6000.3.25f1/Unity/Unity.app/Contents/Localization/ko.po` (2,777,994 bytes).
- After restarting an isolated small temporary project, the File, Edit, Assets, GameObject, Component, Services, and Help menus appeared in Korean. `Window` remained in English.
- The unused Unity 6.6 installation was outside this change.

To repeat the setup, choose Korean in Hub appearance settings, install `language-ko` through `Installs > Manage > Add Modules > Language packs`, then open `Unity > Settings > Languages` on macOS. Enable `Editor Language (Experimental)`, select Korean, and restart the Editor.

Language packs belong to each Editor installation. When upgrading, install the Korean module for the new version and verify the language selection. Module availability varies by version and platform, and some menus or package windows may remain in English.

These are local user preferences, separate from the game's language or content. Verified preferences are `Editor.kEditorLocale = "Korean"` and `Editor.kEnableEditorLocalization = true`; the existing compiler-message localization value remains `false`. Official language packs and Unity binaries remain in the local installation and are excluded from the repository.

## 공식 참고 / Official references

- [Unity Hub 및 Editor 언어 선택 / Select a language](https://docs.unity.com/en-us/hub/add-editor-language)
- [에디터 모듈 추가 / Add Editor modules](https://docs.unity.com/en-us/hub/add-modules)
- [Unity 6.3 환경 설정 경로 / Preferences reference](https://docs.unity3d.com/6000.3/Documentation/Manual/Preferences.html)
- [사용자 환경 설정 저장 / EditorPrefs](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/EditorPrefs.html)
- [Unity 6000.3 언어 설정 코드 / Language preference source](https://github.com/Unity-Technologies/UnityCsReference/blob/6000.3/Editor/Mono/PreferencesWindow/PreferencesSettingsProviders.cs#L1109)
