# 海日和の自動反映

既存Caddyから `https://weather.<CHUCK_DOMAIN>` に静的配信します。既存の `CHUCK_USER` / `CHUCK_PASSWORD_HASH` を利用します。新たなコンテナ・公開ポート・DB・API鍵は不要です。

## 自動更新

VMの既存 `chuck-update.timer` が5分ごとにこのリポジトリと各アプリを取得します。`bin/fetch-apps.sh` は `UeEmon/OpenWeather` のmain（`OPENWEATHER_REF` で変更可能）を取得します。変更があれば既存の設定チェック後にCaddyを更新します。アプリはビルド不要です。OpenWeatherのソースを先にGitHubへ反映してから、この配信設定を反映してください。

`bin/check-config.sh` は4つの配信資産が存在しない場合も起動を止めます。Caddyはこれらの資産だけを配信し、Gitメタデータ、テスト、READMEは公開しません。データは閲覧者のブラウザがOpen-Meteoから直接取得します。

## VMでの確認

```sh
cd ~/oracle-cloud-deploy
systemctl status chuck-update.timer
journalctl -u chuck-update.service -n 30
```

更新後に `https://weather.<CHUCK_DOMAIN>/` で認証なし401、認証あり200と海象値の表示を確認します。認証後も `/.git/config` と `/README.md` は404になります。Caddy reloadの警告がある場合は旧設定が残っている可能性があるためログを確認してください。

## 検証

海日和のNodeテスト4件と、模擬データによるブラウザ操作を検証済み。相模湾沖の実Open-Meteo気象・海象APIの取得を確認済み。一時Caddy 2.8.4で認証401/200、4資産の配信、mjsのJavaScript MIME、非公開ファイル404を確認済み。全システムを含むCompose起動と実VMの認証後表示は別途確認が必要です。
