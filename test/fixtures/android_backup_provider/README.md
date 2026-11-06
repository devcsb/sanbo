# Android 백업 제공자 반례

앱과 분리된 QA 전용 DocumentsProvider다. 사용자 파일을 읽지 않고 합성 백업만
생성한다. 제품 manifest나 APK에는 포함되지 않는다. 별도로 소유한 에뮬레이터에서
시스템 파일 선택기와 실제 descriptor 취소를 검증할 때 설치한다.

```sh
bash test/fixtures/android_backup_provider/build.sh /path/to/android-sdk
/path/to/android-sdk/platform-tools/adb -s EMULATOR_SERIAL install -r -t build/backup-provider-fixture/provider.apk
```

JDK, Android platform 34와 build-tools 36.0.0을 사용한다. 생성 APK와 일회용 QA
서명 키는 무시된 `build/`에만 둔다. 제품 서명 키와 CARTO 키가 필요하지 않다.

산보 설정에서 백업 가져오기를 누르고 시스템 선택기의 ‘산보 보안 QA’를 선택한다.

| 파일 | 반례와 기대 결과 |
|---|---|
| normal | 정상 소형 백업, 확인 후 가져오기 |
| unknown | 크기 metadata 없음, 정상 읽기 |
| huge | 1바이트로 표시하나 실제 50MiB+1, 한도 오류 |
| slow | 1초마다 공백을 보내며 60초 대기, 취소 또는 30초 제한 |
| maximum | 정확히 50MiB, 정상 확인/가져오기 |
| failed | JSON 도중 reliable pipe 오류, 파일 읽기 실패 |
| blocked | 앱의 metadata 조회에 6초 동안 응답하지 않음, 재생성 시 중복 작업 차단 |

slow 읽기 도중 앱 프로세스를 종료한 뒤 다시 열면 앱의 `cache/sanbo_imports`에
남은 사본을 회수해야 한다. 취소 뒤 normal을 선택해 이전 결과가 새 작업을 완료하지
않는지도 확인한다. 앱의 원본 제공자 URI는 삭제하지 않아야 한다.

Activity 재생성도 검사하려면 제품의 기본 debug 서명과 같은 인증서로 QA APK를
서명한다. release 키는 사용하지 않는다. 아래 옵션은 기본 Android debug keystore를
읽어 서명하며, 별도 debug keystore라면 `SANBO_QA_DEBUG_KEYSTORE`로 경로를 지정한다.
기존 QA APK와 인증서가 다르면 QA 패키지만 제거한 뒤 설치한다.

```sh
bash test/fixtures/android_backup_provider/build.sh /path/to/android-sdk --lifecycle
/path/to/android-sdk/platform-tools/adb -s EMULATOR_SERIAL install -r -t build/backup-provider-fixture/provider.apk
/path/to/android-sdk/platform-tools/adb -s EMULATOR_SERIAL shell am force-stop com.sanbo.sanbo
/path/to/android-sdk/platform-tools/adb -s EMULATOR_SERIAL shell am instrument -w -r com.sanbo.qa.documents/.LifecycleProbe
```

`choose slow.sanbo` 상태를 받으면 90초 안에 앱 설정에서 slow를 선택한다. 읽기가
시작되면 QA 코드가 실제 `Activity.recreate()`를 호출한다. Activity 생성 2회 이상(초기와 재생성),
종료 1회 이상, 남은 임시 파일 0개일 때만 결과의 `phase=PASS`를 출력한다.
`INSTRUMENTATION_CODE: -1`은 이 도구의 정상 완료 코드다. 실패도 shell 종료 0일 수
있으므로 `phase`와 각 개수를 확인한다. QA는 앱 작업 스택을 초기화하지만 DB를 지우지 않는다.

`am instrument`에 `-e mode blocked`를 추가하면 blocked를 선택한다. QA는 새 Activity의
native 가져오기 진입점을 호출해 기존 provider가 닫히기 전에 새 작업을 거부하는지도
검사한다. 이 경우 `overlap=import_busy`, `phase=PASS`와 임시 파일 0개를 모두 확인한다.
이 검사는 debug APK 안의 클래스와 메서드를 사용하는 테스트이며 공개 앱의 외부 API가 아니다.
