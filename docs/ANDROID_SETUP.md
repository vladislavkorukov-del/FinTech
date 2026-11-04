# Android toolchain

Установленная и проверенная конфигурация:

- Полный Temurin JDK 21.0.13+9 (`javac`, не только JRE), `/workspace/jdk-21`. Установка: `python3 tool/bootstrap_jdk.py`; архив проверяется по опубликованному SHA-256.
- Flutter 3.47.9 (устанавливается отдельным cloud bootstrap).
- Android command-line tools 23.0.
- Android SDK Platform 36 revision 2, 35 revision 2 и 34 revision 3. Более ранние platform-пакеты требуются native-плагинам.
- Build Tools 36.0.0.
- Platform Tools 37.0.1.
- CMake 3.22.1 (для JNI native-плагинов).
- NDK 28.2.13676358 (версия из `FlutterExtension.kt`).
- Gradle Wrapper 9.3.1, AGP 9.1.0, Kotlin 2.4.0; флаги совместимости из шаблона Flutter.

Из `/workspace/FinTech` выполните:

```sh
python3 tool/bootstrap_jdk.py
python3 tool/bootstrap_android.py
source tool/cloud_env.sh
export ANDROID_HOME=/workspace/android-sdk
export GRADLE_USER_HOME=/workspace/gradle-cache
export PATH="/workspace/flutter-sdk/bin:$ANDROID_HOME/platform-tools:$PATH"
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

`bootstrap_android.py` проверяет размер и опубликованную Google SHA-1 архива command-line tools перед распаковкой, сохраняет TLS-проверку, ставит точные версии SDK официальным Android CLI и проверяет `source.properties`. Источник контрольной суммы — `https://dl.google.com/android/repository/repository2-1.xml`. Temurin использует системное Java-хранилище CA `/etc/ssl/certs/java/cacerts`, включая сертификат штатного HTTPS-прокси; vendor CA сохранены рядом. TLS-проверка не отключается.

SDK Manager 23 перенаправляет на Android CLI; отдельный `sdkmanager --licenses` больше не требуется. Официальный установщик показывает условия Android SDK и создаёт записи принятия лицензий. Телеметрия Android CLI при установке отключена через `--no-metrics`. Эмулятор и образы Android не устанавливаются.

В облаке нужен разрешённый доступ к `dl.google.com`, а для Flutter — к `storage.googleapis.com`. При ограниченном sandbox установка и сеть требуют штатного запуска с повышенными правами. Скрипт не обходит сетевую политику и не отключает проверку сертификатов. Прокси и доверенные CA наследуются от среды. Для Java скрипт переводит имя и порт штатного `HTTPS_PROXY` в JVM proxy flags, не извлекая и не печатая credentials.

Gradle не читает `HTTPS_PROXY` автоматически. В текущей среде проверен такой запуск из каталога `android`:

```sh
GRADLE_USER_HOME=/workspace/gradle-cache \
GRADLE_OPTS='-Dhttp.proxyHost=proxy -Dhttp.proxyPort=8080 -Dhttps.proxyHost=proxy -Dhttps.proxyPort=8080' \
./gradlew help --no-daemon --console=plain --max-workers=2
```

Эта команда завершилась `BUILD SUCCESSFUL` после установки SDK и NDK. Это проверяет Gradle-конфигурацию, но не доказывает сборку APK: для неё нужны бинарные артефакты Flutter и разрешённые зависимости Pub.

`android/local.properties` — локальный игнорируемый файл. В текущей машине он содержит пути к SDK и Flutter. `flutter` обычно обновляет его самостоятельно; не коммитьте пути конкретной машины. Настройка release-подписи описана в [SECURITY.md](SECURITY.md).
