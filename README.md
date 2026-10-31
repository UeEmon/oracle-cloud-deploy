# oracle-cloud-deploy

Oracle Cloud（東京リージョン、A1は無料枠内）のVM 1台で、複数の開発中システムを動かすための構成です。各システムのコードと設定はそれぞれのリポジトリに置き、このリポジトリはVMとHTTPSの入口だけを管理します。

| システム | リポジトリ | URLの例 | ログイン |
|---|---|---|---|
| CHUCK（公開版） | UeEmon/CHUCK-public- | `https://<IP>.sslip.io` | なし（誰でも使える。計算回数の制限あり） |
| CHUCK 管理サイト | 同上 | `https://admin.<IP>.sslip.io` | Caddyのパスワード |
| CHUCK 公開データ取得用コンテナの管理画面 | 同上 | `https://data.<IP>.sslip.io` | `HF_PUBLIC_DATA_UI_PASSWORD`（取得用コンテナ自身のログイン）。CHUCK連携用の `/api/*` は公開しない |
| 要件ナビ | UeEmon/ai-requirements-navigator | `https://arn.<IP>.sslip.io` | 要件ナビ自身のログイン（`AUTH_MODE=local`） |
| HACS 送信 | UeEmon/HACS | `https://hacs.<IP>.sslip.io` | Caddyのパスワード（CHUCK管理サイトと同じ） |
| HACS 受信 | 同上 | `https://hacs-rx.<IP>.sslip.io` | 同上 |
| eNMEA2000（NMEA Observatory本体） | UeEmon/eNMEA2000 | `https://nmea.<IP>.sslip.io` | `env/enmea.env` の `APP_TOKEN` |
| BACCHUS-SYSTEM | UeEmon/BACCHUS-SYSTEM | `https://bacchus.<IP>.sslip.io` | 個人用はなし（ブラウザ内に保存）。共用は `env/bacchus.env` の `BACCHUS_USERS` のトークン |
| altpnt（代替PNTシミュレータAPI） | UeEmon/altpnt | `https://altpnt.<IP>.sslip.io/docs` | Caddyのパスワード（CHUCK管理サイトと同じ） |

`<IP>` は予約済み公開IPのドットをハイフンにしたもの。独自ドメインがあれば置き換える。

CHUCKは公開版（`compose.public.yaml` で `public_server.py` を起動）を使う。管理者かどうかは、管理サイトでだけCaddyが付ける `X-Chuck-Admin` ヘッダー（値は `CHUCK_ADMIN_SECRET`）で判定し、公開サイトでは利用者が送っても消す。本家（UeEmon/VOCAP-COMPATIBILITY-）は非公開。公開版は UeEmon/CHUCK-public- に置き、本家の履歴は含めない。

## 構成

- 入口はCaddy 1つ。80／443だけを公開し、Let's Encryptの証明書を自動で取る。
- 各システムのWeb・DB・ゲートウェイは、VM内の127.0.0.1にだけ公開する。管理画面は `ssh -L` で開く。
- 例外はCHUCK位置ゲートウェイのNMEA 0183受信（TCP・UDP 10120、`overrides/chuck.yaml`）。機器がインターネットから直接送るため全体に開け、局ごとの受信キーを必須にする（`bin/check-config.sh` が確認）。eNMEA2000が10110を使っているので10120にしている。ゲートウェイの管理画面とHTTPのAPIは127.0.0.1のまま。
- `compose.yaml` が各アプリのcompose を `include` で読み込む。アプリ側の設定は変更しない。

作業の経緯と現在の状態は [引き継ぎ書](docs/HANDOVER.md) を参照。

altpntはeNMEA2000と同じく別プロジェクト（`-p altpnt`）で、API（`cloud`）だけを起動する。LLM解析（LiteLLM）とエッジのシナリオ実行は起動しない。使うときは `env/altpnt.env` に `ANTHROPIC_API_KEY` を書き、`docker compose -p altpnt --env-file env/altpnt.env -f apps/altpnt/docker-compose.yml -f overrides/altpnt.yaml up -d litellm`。altpntのビルドに失敗しても、他のシステムの更新は止まらない。保存するデータがないのでバックアップの対象外。

## Oracle Cloudの資源

| 資源 | 内容 |
|---|---|
| リージョン | ap-tokyo-1（ホームリージョン。Always Freeはここだけ） |
| ネットワーク | VCN `chuck-vcn` 10.0.0.0/16、公開サブネット 10.0.0.0/24、インターネットゲートウェイ |
| セキュリティ・リスト | TCP 80／443、UDP 443は全体から。TCP・UDP 10120（CHUCK位置ゲートウェイのNMEA受信）も全体から。TCP 22は管理者のIPからだけ |
| VM | `VM.Standard.A1.Flex`、Ubuntu 24.04 aarch64、ブート50GB、予約済み公開IP、ユーザーデータ `cloud-init.yaml` |

無料枠はA1合計4 OCPU・24GB（2026年6月以降、無料アカウントは2 OCPU・12GB）、ブロック・ストレージ合計200GB。アカウントは従量課金なので、超えた分は課金される。

## 初回の展開

```sh
cd ~/oracle-cloud-deploy
bin/fetch-apps.sh
cp env.example .env               # ドメイン、CHUCK管理サイトのパスワードのハッシュ、CHUCK_ADMIN_SECRET、寄付の設定
cp env/arn.env.example env/arn.env  # MASTER_KEY、LOCAL_SETUP_TOKEN、PUBLIC_URL
bin/check-config.sh               # 要件ナビが開発用ログインのまま、CHUCKが本家のまま公開されないことを確認
bin/up.sh                         # 本体の compose と、別プロジェクトの eNMEA2000 を起動
```

`bin/fetch-apps.sh` は最後に `bin/init-secrets.sh` を呼び、所有者の入力が要らない `env/enmea.env`（`APP_TOKEN`、DBのパスワード）と `env/bacchus.env`（所有者用の共用トークン）を、なければ乱数で作る。既存のファイルは変えない。値はVMで `grep APP_TOKEN env/enmea.env` のように読む。

パスワードのハッシュは `docker run --rm caddy:2.8.4 caddy hash-password --plaintext '<パスワード>'` で作り、単引用符付きで書く。平文のパスワード、`CHUCK_ADMIN_SECRET`、`GITHUB_SPONSORS_WEBHOOK_SECRET`、`MASTER_KEY`、`LOCAL_SETUP_TOKEN` はVMに置く `.env` 類と管理者の手元にだけ保管し、このリポジトリには入れない。

## CHUCK位置ゲートウェイのNMEA受信

船舶・航空機・車両の機器は、`<公開IP>:10120` へTCPまたはUDPでNMEA 0183を送ります。最初の1行（UDPは各データグラムの1行目）に局の受信キーを送ります。受信キーはゲートウェイの管理画面で発行します。

```sh
ssh -i ~/.ssh/chuck_oci -L 18083:127.0.0.1:18083 ubuntu@<公開IP>   # http://localhost:18083/ を開く
```

管理画面のログインには `.env` の `HF_GATEWAY_UI_PASSWORD`（16文字以上）が要ります。本体の移動局表示には `HF_POSITION_GATEWAY_TOKEN`、HTTPでの送信には `HF_POSITION_INGEST_TOKEN`（どちらも32文字以上で別の値）を設定します。機能確認はCHUCKの `scripts/gateway_simulator.py check --url http://localhost:18083 --nmea-host <公開IP> --nmea-port 10120` で行えます（CHUCKの `docs/GATEWAY_SIMULATOR.md`）。

## 確認

- `https://<CHUCKのドメイン>/` が認証なしで200になり、AI設定などの管理機能は403
- `https://<CHUCKのドメイン>/api/public-config` に `X-Chuck-Admin` を付けて送っても `admin` が `false`
- `https://admin.<CHUCKのドメイン>/` が認証なしで401、認証付きで200になり、`/api/public-config` の `admin` が `true`
- CHUCKで東京→グアムを計算し、`docker compose restart` 後も結果のURLで開ける
- `https://<要件ナビのドメイン>/` で初期設定画面が開き、`LOCAL_SETUP_TOKEN` なしでは進めない

## 更新と停止

```sh
bin/fetch-apps.sh && bin/check-config.sh && bin/up.sh
docker compose -p enmea down; docker compose down   # -v はデータと証明書を消すので使わない
```

## 自動更新

`chuck-update.timer` が5分ごとに `bin/auto-update.sh` を動かします。このリポジトリを `git pull --ff-only` し、`bin/fetch-apps.sh` でCHUCKと要件ナビを取り込み、要件ナビのCIが公開したイメージを `docker compose pull app` で取得し、前回の反映から何か（コミットまたは要件ナビのイメージ）が変わっていれば `bin/check-config.sh` のあとに `bin/up.sh` します。設定チェックに失敗したときは反映せず、次の回にやり直します。反映した版は `.deployed` に記録します。

```sh
sudo cp systemd/chuck-update.* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now chuck-update.timer
journalctl -u chuck-update.service -n 20    # 直近の結果
```

止めるときは `sudo systemctl disable --now chuck-update.timer`。`systemd/` の中身を変えたときは、上の `cp` からやり直します。

## 運営費の自動反映

CHUCKの寄付メーターの「運営費の目安」は、`.env` の `CHUCK_MONTHLY_COST_USD`（固定分）に、Oracleの請求額を足した金額です。`bin/update-cost.sh` がVM自身の権限（インスタンス・プリンシパル）で請求額を読み、先月の合計と今月の途中額の大きい方をCHUCKに送ります。円の請求は `CHUCK_JPY_PER_USD` でドルに換算します。

Oracle側に、このVMだけを含む動的グループ `chuck-cost-reader` と、ポリシー `Allow dynamic-group chuck-cost-reader to read usage-reports in tenancy` が必要です（読み取り専用）。毎日動かすには:

```sh
bin/update-cost.sh                       # 一度手で動かして結果を確認
sudo cp systemd/chuck-cost.* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now chuck-cost.timer
journalctl -u chuck-cost.service -n 5    # 直近の結果
```

## バックアップ

`chuck-backup.timer` が毎日3:00（JST）ごろに `bin/backup.sh` を動かし、全システムのデータをObject Storageのバケット `chuck-backups`（`.env` の `BACKUP_BUCKET`）に `<日時>/` の下に保存します。`BACKUP_KEEP_DAYS`（既定14日）より古いものは消します。

| ファイル | 中身 |
|---|---|
| `arn.pgdump`、`enmea.pgdump` | 要件ナビとeNMEA2000のPostgreSQL（`pg_dump --format=custom`） |
| `hf-data.tar.gz`、`gateway-data.tar.gz` | CHUCKの計算結果・寄付台帳・位置情報（SQLiteはバックアップAPIで一貫した写しを取る） |
| `artifacts.tar.gz` | 要件ナビの成果物ファイル |
| `hacs_data.tar.gz`、`bacchus-data.tar.gz`、`enmea-raw-data.tar.gz` | HACSのプリセット、BACCHUSの在庫、eNMEA2000の受信ログ |

秘密の値（`.env`、`env/*.env`）とCaddyの証明書は含めない。秘密の値の控えは所有者のMacの `~/.chuck-deploy` にある。

Oracle側に、非公開のバケット `chuck-backups` と、chuck-1だけを含む動的グループ（`chuck-cost-reader` を流用）への書き込み権限が必要です。

```
Allow dynamic-group chuck-cost-reader to manage objects in tenancy where target.bucket.name='chuck-backups'
```

```sh
bin/backup.sh                            # 一度手で動かして結果を確認
sudo cp systemd/chuck-backup.* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now chuck-backup.timer
journalctl -u chuck-backup.service -n 5  # 直近の結果
```

戻すときは、Oracleのコンソールか `oci os object get` で取り出し、PostgreSQLは `pg_restore --clean --if-exists -U <ユーザー> -d <DB>`、ボリュームはサービスを止めてから `tar xzf` で中身を置き換える。

## システムを追加するとき

1. `bin/fetch-apps.sh` に取得先を追加する
2. `compose.yaml` の `include` に、そのシステムのcomposeを追加する。ポートは127.0.0.1に限る。ポートが他と重なるときは `overrides/` に `!override` で書き換えるファイルを置く。サービス名（`app`、`db` など）が他と重なるときは、eNMEA2000のように別プロジェクトにして `bin/up.sh` で起動し、`edge` ネットワークでCaddyとつなぐ
3. `caddy/Caddyfile` にサイトを追加する。ログインがないシステムには `basic_auth` を付ける
4. メモリとディスクが無料枠に収まるか確認する
5. データを持つなら `bin/backup.sh` に追加する
