# Jelly Music

Player de música pessoal sobre Jellyfin. Alvos: **Android** e **Windows** (Linux depois).
Especificação: `docs/especificacao_requisitos_app_musica_jellyfin.docx` (v1.1).

## Estado atual: F0 — spike técnico
Login no Jellyfin → lista/busca de faixas → reprodução do arquivo **original** (`static=true`)
→ painel que confirma se o servidor entregou o original (compara o tamanho do stream com o do arquivo).
Há um switch para tocar a versão transcodificada (MP3 192k) e comparar.

## Primeira execução
Pré-requisitos: Flutter estável, Android SDK, e no Windows o Visual Studio com "Desktop development with C++".

```bash
cd jelly_music
flutter create . --org com.evmartins --project-name spotifin --platforms=android,windows,linux
flutter pub get
flutter test
flutter run -d windows     # ou: flutter run -d <id-do-android>
```
`flutter create .` gera as pastas `android/`, `windows/` e `linux/` sem tocar em `lib/` e `pubspec.yaml`.

### Ajustes necessários no Android
- `android/app/src/main/AndroidManifest.xml`: dentro de `<application>` adicione
  `android:usesCleartextTraffic="true"` se o Jellyfin estiver em HTTP na LAN (use HTTPS fora dela, RNF-005).
- `android/app/build.gradle(.kts)`: `minSdk` = 23 (exigido por flutter_secure_storage).

## Checklist do spike (critério de saída da F0)
- [ ] Roda no Android e no Windows
- [ ] Login e listagem de faixas funcionam
- [ ] FLAC 16/44.1, 24/48, 24/96 (e 24/192 se possível) tocam sem falhas
- [ ] Painel mostra "Original entregue" nos FLACs
- [ ] Confirmar no dashboard/logs do Jellyfin que não houve transcodificação
- [ ] Seek funciona em arquivos grandes
