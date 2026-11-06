# 海日和の自動反映

既存Caddyから `https://weather.<CHUCK_DOMAIN>` に静的配信します。既存の `CHUCK_USER` / `CHUCK_PASSWORD_HASH` を利用します。共通収集コンテナ `ocean-data` が外部データをSQLiteへ保存し、海日和はCaddy経由でAPIを利用します。追加の公開ポートやAPI鍵は不要です。

## 自動更新

VMの既存 `chuck-update.timer` が5分ごとにこのリポジトリと各アプリを取得します。`bin/fetch-apps.sh` は `UeEmon/OpenWeather` のmain（`OPENWEATHER_REF` で変更可能）を取得します。変更があれば既存の設定チェック後にCaddyを更新します。Webはビルド不要で、共通収集コンテナは `apps/OpenWeather/collector` からビルドします。OpenWeatherのソースを先にGitHubへ反映してから、この配信設定を反映してください。

`bin/check-config.sh` はWeb資産・収集コンテナのソースが存在しない場合も起動を止めます。Caddyはこれらの資産だけを配信し、Gitメタデータ、テスト、READMEは公開しません。データは `ocean-data` がデータごとの取得周期で取得します。ブラウザは同一オリジンの `/api/v1/weather` と `/api/v1/marine` を使い、内部の各システムは `http://ocean-data:8080` へ接続できます。API仕様はOpenWeatherの `collector/README.md` を参照してください。

## VMでの確認

```sh
cd ~/oracle-cloud-deploy
systemctl status chuck-update.timer
journalctl -u chuck-update.service -n 30
```

更新後に `https://weather.<CHUCK_DOMAIN>/` で認証なし401、認証あり200と海象値の表示を確認します。認証後も `/.git/config` と `/README.md` は404になります。Caddy reloadの警告がある場合は旧設定が残っている可能性があるためログを確認してください。

## 検証

海日和のNodeテスト4件と、模擬データによるブラウザ操作を検証済み。相模湾沖の実Open-Meteo気象・海象APIの取得を確認済み。一時Caddy 2.8.4で認証401/200、4資産の配信、mjsのJavaScript MIME、非公開ファイル404を確認済み。全システムを含むCompose起動と実VMの認証後表示は別途確認が必要です。

## 共通収集コンテナ

`ocean-data` は既存Composeのデフォルトネットワークに参加し、ホストへポートを公開しません。同じネットワークのCHUCK・要件ナビ・BACCHUS等のバックエンドからAPIに到達できます。現在、実際にAPIを読む実装を追加したクライアントは海日和です。他アプリの業務ロジックへの組み込みは、それぞれのリポジトリでこのAPI契約を使って行います。

```sh
docker compose exec -T ocean-data python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/ready').status)"
docker compose logs --tail 30 ocean-data
```

起動直後は初回収集が終わるまで `/ready` と未取得APIが503になります。`/health` は生存確認専用です。収集失敗時は前回正常データを保存し、APIの `_meta.last_collection_failed` と `_meta.stale` を各クライアントが判定します。気象・海象APIは現在Open-Meteoのみで、他の調査済みデータ提供元は未接続です。

永続ボリューム `ocean-data` は既存の日次バックアップにも含めます。収集コンテナのメモリ上限は256MB、CPU上限は0.5です。既存サービスに新たなホスト公開ポートや外部データ取得処理は追加しません。

## 追加ソース・スケジュール・GIS

有効な収集元・再配布条件はOpenWeatherの `collector/sources.json` と `collector/LEGAL_REVIEW.md` を参照。気象30分、海象60分、気象庁の海上図／台風索引は毎時10分、NOAA OISST Finalは毎日03:00 JST。更新元の公開時刻が未確認の場合、こちらの取得時刻と同一視しません。予定・失敗回数はSQLiteに保存します。

CesiumJSによる2D/3D GISで矩形海域を保存できます。予報は中心点の代表値です。追加海域は同じサーバー利用者の共有設定で最大24件。日本の国土地理院DEM提供範囲で陸上地形を表示し、海底地形は未接続です。地図／標高タイルは対話表示時にブラウザが直接取得し、一括収集しません。Referrer-PolicyはOSMタイル方針に従いstrict-origin-when-cross-originです。

新API: `/api/v1/sources`, `/api/v1/sst-analysis?area=...`, `/api/v1/jma-marine-bulletins`, `/api/v1/jma-typhoon-bulletins`。海域のGET/POST `/api/v1/areas` とDELETE `/api/v1/areas/{id}` は既存のBasic認証の後で利用します。データ源に未取得がある場合でもWeb・気象・海象APIは稼働を続けます。全ソースを確認する `/ready` は未取得時503です。

時間窓は `window=history`（過去12時間）、`window=24`、`window=36` をweather/marine APIに指定します。hourlyの毎時モデル値を抽出し、現在値と日別予報は元の構造を保持します。過去分を観測実況とは表示しません。Web上の時間選択にも反映します。
