# oracle-cloud-deploy

Oracle Cloud（東京リージョン、A1は無料枠内）のVM 1台で、複数の開発中システムを動かすための構成です。各システムのコードと設定はそれぞれのリポジトリに置き、このリポジトリはVMとHTTPSの入口だけを管理します。

| システム | リポジトリ | URLの例 | ログイン |
|---|---|---|---|
| CHUCK（公開版） | UeEmon/CHUCK-public- | `https://<IP>.sslip.io` | なし（誰でも使える。計算回数の制限あり） |
| CHUCK 管理サイト | 同上 | `https://admin.<IP>.sslip.io` | Caddyのパスワード |
| 要件ナビ | UeEmon/ai-requirements-navigator | `https://arn.<IP>.sslip.io` | 要件ナビ自身のログイン（`AUTH_MODE=local`） |

`<IP>` は予約済み公開IPのドットをハイフンにしたもの。独自ドメインがあれば置き換える。

CHUCKは公開版（`compose.public.yaml` で `public_server.py` を起動）を使う。管理者かどうかは、管理サイトでだけCaddyが付ける `X-Chuck-Admin` ヘッダー（値は `CHUCK_ADMIN_SECRET`）で判定し、公開サイトでは利用者が送っても消す。本家（UeEmon/VOCAP-COMPATIBILITY-）は非公開。公開版は UeEmon/CHUCK-public- に置き、本家の履歴は含めない。

## 構成

- 入口はCaddy 1つ。80／443だけを公開し、Let's Encryptの証明書を自動で取る。
- 各システムのWeb・DB・ゲートウェイは、VM内の127.0.0.1にだけ公開する。管理画面は `ssh -L` で開く。
- `compose.yaml` が各アプリのcompose を `include` で読み込む。アプリ側の設定は変更しない。

作業の経緯と現在の状態は [引き継ぎ書](docs/HANDOVER.md) を参照。

## Oracle Cloudの資源

| 資源 | 内容 |
|---|---|
| リージョン | ap-tokyo-1（ホームリージョン。Always Freeはここだけ） |
| ネットワーク | VCN `chuck-vcn` 10.0.0.0/16、公開サブネット 10.0.0.0/24、インターネットゲートウェイ |
| セキュリティ・リスト | TCP 80／443、UDP 443は全体から。TCP 22は管理者のIPからだけ |
| VM | `VM.Standard.A1.Flex`、Ubuntu 24.04 aarch64、ブート50GB、予約済み公開IP、ユーザーデータ `cloud-init.yaml` |

無料枠はA1合計4 OCPU・24GB（2026年6月以降、無料アカウントは2 OCPU・12GB）、ブロック・ストレージ合計200GB。アカウントは従量課金なので、超えた分は課金される。

## 初回の展開

```sh
cd ~/oracle-cloud-deploy
bin/fetch-apps.sh
cp env.example .env               # ドメイン、CHUCK管理サイトのパスワードのハッシュ、CHUCK_ADMIN_SECRET、寄付の設定
cp env/arn.env.example env/arn.env  # MASTER_KEY、LOCAL_SETUP_TOKEN、PUBLIC_URL
bin/check-config.sh               # 要件ナビが開発用ログインのまま、CHUCKが本家のまま公開されないことを確認
docker compose up -d --build
```

パスワードのハッシュは `docker run --rm caddy:2.8.4 caddy hash-password --plaintext '<パスワード>'` で作り、単引用符付きで書く。平文のパスワード、`CHUCK_ADMIN_SECRET`、`GITHUB_SPONSORS_WEBHOOK_SECRET`、`MASTER_KEY`、`LOCAL_SETUP_TOKEN` はVMに置く `.env` 類と管理者の手元にだけ保管し、このリポジトリには入れない。

## 確認

- `https://<CHUCKのドメイン>/` が認証なしで200になり、AI設定などの管理機能は403
- `https://<CHUCKのドメイン>/api/public-config` に `X-Chuck-Admin` を付けて送っても `admin` が `false`
- `https://admin.<CHUCKのドメイン>/` が認証なしで401、認証付きで200になり、`/api/public-config` の `admin` が `true`
- CHUCKで東京→グアムを計算し、`docker compose restart` 後も結果のURLで開ける
- `https://<要件ナビのドメイン>/` で初期設定画面が開き、`LOCAL_SETUP_TOKEN` なしでは進めない

## 更新と停止

```sh
bin/fetch-apps.sh && bin/check-config.sh && docker compose up -d --build
docker compose down        # -v は全システムのデータと証明書を消すので使わない
```

## 運営費の自動反映

CHUCKの寄付メーターの「運営費の目安」は、`.env` の `CHUCK_MONTHLY_COST_USD`（固定分）に、Oracleの請求額を足した金額です。`bin/update-cost.sh` がVM自身の権限（インスタンス・プリンシパル）で請求額を読み、先月の合計と今月の途中額の大きい方をCHUCKに送ります。円の請求は `CHUCK_JPY_PER_USD` でドルに換算します。

Oracle側に、このVMだけを含む動的グループ `chuck-cost-reader` と、ポリシー `Allow dynamic-group chuck-cost-reader to read usage-reports in tenancy` が必要です（読み取り専用）。毎日動かすには:

```sh
bin/update-cost.sh                       # 一度手で動かして結果を確認
sudo cp systemd/chuck-cost.* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now chuck-cost.timer
journalctl -u chuck-cost.service -n 5    # 直近の結果
```

## システムを追加するとき

1. `bin/fetch-apps.sh` に取得先を追加する
2. `compose.yaml` の `include` に、そのシステムのcomposeを追加する。ポートは127.0.0.1に限る
3. `caddy/Caddyfile` にサイトを追加する。ログインがないシステムには `basic_auth` を付ける
4. メモリとディスクが無料枠に収まるか確認する
