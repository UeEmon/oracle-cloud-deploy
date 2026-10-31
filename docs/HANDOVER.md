# Oracle Cloud デプロイ 引き継ぎ書

作成日：2026年10月17日（JST）。CHUCKプロジェクトのスレッドから、Oracle Cloudの管理をこのリポジトリと専用のClaudeプロジェクトへ移した。

## 1 決まっていること

- Oracle Cloudのホームリージョン東京（ap-tokyo-1）を使う。2026-10-17、所有者が「Always Freeのみ」の制約を解除し、従量課金アカウントでA1を無料枠内で取る方針にした。有料のVM種別や他リージョンへの切り替えは、引き続き所有者の指示を待つ。
- VM 1台にCHUCKと要件ナビを相乗りさせる。2026-10-20、所有者の指示でHACS・eNMEA2000（本体のみ）・BACCHUS-SYSTEMも同じVMに載せる。HACSはログインがないのでCHUCK管理サイトと同じパスワードの後ろに置く。eNMEA2000のNMEA受信ポート（UDP 10110・TCP 10111）はVM内だけに開き、外に開けるかは所有者の判断を待つ。公開の入口はCaddy 1つで、80／443だけを開ける。
- CHUCKは公開版（UeEmon/CHUCK-public-）を誰でも使える形で公開する。管理機能は `admin.<ドメイン>` に置き、CaddyのBasic認証の後で `X-Chuck-Admin` を付ける。本家は非公開のまま、公開版は本家の履歴を含めずに公開する（所有者の指示、2026-10-17）。要件ナビは自前の `AUTH_MODE=local` を使い、`LOCAL_SETUP_TOKEN` を設定する。
- 所有者は「80/443をインターネットに公開してよい」「要件ナビも同じVMに公開してよい」と明示的に許可済み。
- 公開IPは予約済みIPを使い、URLは `<IP>.sslip.io`、`admin.<IP>.sslip.io`、`arn.<IP>.sslip.io` にする。
- 2026-10-27、所有者の指示で altpnt（UeEmon/altpnt、代替PNTシミュレータのAPI）も同じVMに載せる。ログインがないのでCHUCK管理サイトと同じパスワードの後ろに置き、別プロジェクト（`-p altpnt`）でAPIだけを動かす。LiteLLMは起動しない。
- 2026-10-31、所有者の指示でCHUCK位置ゲートウェイのNMEA 0183受信をインターネットに開ける。eNMEA2000が10110を使っているのでTCP・UDP 10120を全体に開け、局ごとの受信キーを必須にする（`overrides/chuck.yaml`）。ゲートウェイの管理画面とHTTP APIは127.0.0.1のまま。
- 当面は1 OCPU・6GBで作り、空きが出たら2 OCPU・12GBに戻す（所有者の指示）。
- 検証が終わったら、確認なしで後片付けまで自動で行う（既存の資源には触れない）。所有者の指示。
- パスワード、ハッシュ以外の鍵、`.env` 類はリポジトリに入れない。このリポジトリは公開。

## 2 現在の状態（2026-10-17 14:00 UTC）

| 対象 | 状態 |
|---|---|
| テナンシー | `UeEmonCloud`、従量課金（PAYG、UPGRADED を確認）、ホーム ap-tokyo-1（AD-1のみ） |
| ネットワーク | VCN `chuck-vcn` 10.0.0.0/16、公開サブネット `chuck-public` 10.0.0.0/24、インターネットゲートウェイ `chuck-igw` |
| セキュリティ・リスト `chuck-sl` | TCP 80／443・UDP 443は0.0.0.0/0、TCP 22は所有者のMacのIP（作成時 60.120.190.28/32）だけ、ICMP 3/4 |
| VM `chuck-1` | 2026-10-17 13:34 UTC作成、RUNNING。A1 1 OCPU・6GB、ブート50GB、プライベートIP 10.0.0.93 |
| 予約済み公開IP `chuck-ip` | 168.110.7.225（chuck-1に割り当て済み） |
| 公開URL | CHUCK `https://168-110-7-225.sslip.io`、管理 `https://admin.168-110-7-225.sslip.io`、要件ナビ `https://arn.168-110-7-225.sslip.io`。証明書はLet's Encrypt（2027-01-15まで） |
| VMの構成 | Docker公式版（Compose v5.6.0）。旧cloud-initはIP割当前で外へ出られずパッケージ導入に失敗したため、本リポジトリの `cloud-init.yaml` の手順を手で実施。本リポジトリは `~/oracle-cloud-deploy` |
| 寄付 | 有効（GitHub Sponsors、1回 $5 のTier、Webhook登録済み）。秘密の値はMacの `~/.chuck-deploy/sponsors_webhook_secret` |
| 自動更新 | `chuck-update.timer` が5分ごとにマージ済みの変更を取り込んで反映する（READMEの「自動更新」）。Macは不要 |
| 運営費 | 動的グループ `chuck-cost-reader`（chuck-1のみ）とポリシー `chuck-cost-reader`（`read usage-reports`）を作成済み。`chuck-cost.timer` が毎日請求額を寄付メーターに送る（READMEの「運営費の自動反映」） |
| 要件ナビ | 初期設定待ち（組織と最初の管理者は未作成）。所有者が `LOCAL_SETUP_TOKEN` で行う |
| ログイン | MacのOCI CLIはブラウザ・セッション（`oci session authenticate --profile-name DEFAULT --region ap-tokyo-1`）。切れたら所有者のブラウザ・ログインが必要 |

Mac（所有者のMacBook Air、arm64）に置いたもの（すべて権限600、リポジトリには入れない）：

- SSH鍵 `~/.ssh/chuck_oci`（`ssh -i ~/.ssh/chuck_oci ubuntu@168.110.7.225`）
- CHUCK管理サイトのパスワード `~/.chuck-deploy/password` とハッシュ `password.bcrypt`
- `~/.chuck-deploy/chuck_admin_secret`、`arn_master_key`、`arn_setup_token`（VMが使う値。同じフォルダの古い `master_key`・`local_setup_token` は使っていない）
- 各資源のOCID `~/.chuck-deploy/oci-ids.env`（`INST`、`PIP`、`IP` を含む）
- OCI CLI 3.95.0（Homebrew）、`OCI_CLI_AUTH=security_token`、プロファイル DEFAULT
- 再試行スクリプト `~/.chuck-deploy/bin/launch-retry.sh`（成功して終了済み）

MacにはGitHubの認証がない。GitHubへの書き込みはクラウド側のスレッドで行う。MacのClaudeでOCIの資源を作る操作は、Macの自動許可で止まるため、所有者の明示の指示が要る。

## 3 VMができた後の手順（2026-10-17、手順1～6は完了）

1. 予約済み公開IPを作り、`chuck-1` のプライマリVNICのプライベートIPに割り当てる。`cloud-init status --wait` で初期設定の完了を待つ。
2. 旧cloud-initで入るのは Ubuntu の `docker.io` と古い `docker-compose-v2`。`include` の `env_file` にはCompose 2.24以上が必要なので、`docker compose version` を確認し、足りなければDocker公式リポジトリの `docker-compose-plugin` を入れる（本リポジトリの `cloud-init.yaml` と同じ手順）。
3. `/home/ubuntu/VOCAP-COMPATIBILITY-`（旧cloud-initのクローン）は不要なので消し、本リポジトリをクローンする。
4. READMEの「初回の展開」に従う。秘密の値（パスワードのハッシュ、`MASTER_KEY`、`LOCAL_SETUP_TOKEN`）はMacで作り、控えをMacの `~/.chuck-deploy` に権限600で残す。
5. **`bin/check-config.sh` が通るまで起動しない。** 要件ナビのcomposeは `AUTH_MODE` が空だと開発用ログイン（誰でも管理者）になる。
6. READMEの「確認」をすべて行う。加えて、外部からPostgreSQL（5432）とCHUCKのゲートウェイ（18083）に届かないことを確かめる。
7. 30分おき・最長6時間で、`oci compute instance update --shape-config` により2 OCPU・12GBへの変更を試す。変更でVMが再起動したら、コンテナが戻りHTTPSが応答することを確かめる。

## 4 検証済みのこと

- CHUCKのDocker完成イメージは、Apple Silicon（arm64）のMacで検証済み（キャッシュなしビルド、両サービス起動、東京→グアム、CSV、再起動後の履歴、VOACAP比較で差0）。
- Caddyの設定は `caddy validate` を通過。ローカルでの試験で、認証なし401・認証付き200、同一オリジンの保存は通り別オリジンは403になることを確認。
- `docker compose config` で2システムの結合を確認。`bin/check-config.sh` は `AUTH_MODE=dev` のとき失敗することを確認。
- 2026-10-17、実VM上でREADMEの「確認」をすべて通過（公開200・管理API 403、ヘッダー偽装無効、管理サイト401／200、東京→グアムと再起動後の結果URL、要件ナビのトークンなし403、5432・18083ほか外から不通、Let's Encryptの実証明書）。

## 5 関連

- CHUCK公開版：https://github.com/UeEmon/CHUCK-public-（公開版。設定は `docs/PUBLIC_DEPLOYMENT.md`、寄付は `docs/SPONSORS_SETUP.md`）
- CHUCK本家：https://github.com/UeEmon/VOCAP-COMPATIBILITY-（非公開。`docs/HANDOVER.md` にアプリ側の引き継ぎ）
- 要件ナビ：https://github.com/UeEmon/ai-requirements-navigator（公開イメージ `ghcr.io/ueemon/ai-requirements-navigator` はarm64対応）
- 無料枠の上限：A1合計4 OCPU・24GB、E2.1.Micro 2台、ブロック・ストレージ合計200GB、外向き通信 月10TB
