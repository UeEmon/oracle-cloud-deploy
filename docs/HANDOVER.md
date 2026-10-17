# Oracle Cloud デプロイ 引き継ぎ書

作成日：2026年10月17日（JST）。CHUCKプロジェクトのスレッドから、Oracle Cloudの管理をこのリポジトリと専用のClaudeプロジェクトへ移した。

## 1 決まっていること

- Oracle Cloudのホームリージョン東京（ap-tokyo-1）を使う。2026-10-17、所有者が「Always Freeのみ」の制約を解除し、従量課金アカウントでA1を無料枠内で取る方針にした。有料のVM種別や他リージョンへの切り替えは、引き続き所有者の指示を待つ。
- VM 1台にCHUCKと要件ナビを相乗りさせる。公開の入口はCaddy 1つで、80／443だけを開ける。
- CHUCKは公開版（UeEmon/CHUCK-public-）を誰でも使える形で公開する。管理機能は `admin.<ドメイン>` に置き、CaddyのBasic認証の後で `X-Chuck-Admin` を付ける。本家は非公開のまま、公開版は本家の履歴を含めずに公開する（所有者の指示、2026-10-17）。要件ナビは自前の `AUTH_MODE=local` を使い、`LOCAL_SETUP_TOKEN` を設定する。
- 所有者は「80/443をインターネットに公開してよい」「要件ナビも同じVMに公開してよい」と明示的に許可済み。
- 公開IPは予約済みIPを使い、URLは `<IP>.sslip.io`、`admin.<IP>.sslip.io`、`arn.<IP>.sslip.io` にする。
- 当面は1 OCPU・6GBで作り、空きが出たら2 OCPU・12GBに戻す（所有者の指示）。
- 検証が終わったら、確認なしで後片付けまで自動で行う（既存の資源には触れない）。所有者の指示。
- パスワード、ハッシュ以外の鍵、`.env` 類はリポジトリに入れない。このリポジトリは公開。

## 2 現在の状態（2026-10-16 20:00 UTC）

| 対象 | 状態 |
|---|---|
| テナンシー | `UeEmonCloud`、従量課金アカウント、ホーム ap-tokyo-1（AD-1のみ） |
| ネットワーク | 作成済み：VCN `chuck-vcn` 10.0.0.0/16、公開サブネット `chuck-public` 10.0.0.0/24、インターネットゲートウェイ `chuck-igw`（既定ルート表に0.0.0.0/0） |
| セキュリティ・リスト `chuck-sl` | TCP 80／443・UDP 443は0.0.0.0/0、TCP 22は所有者のMacのIP（作成時 60.120.190.28/32）だけ、ICMP 3/4 |
| VM `chuck-1`、予約済み公開IP | **未作成**。2026-10-16 19:34 UTC以降、2 OCPU・12GB、1 OCPU・6GBとも「Out of host capacity」 |
| 自動再試行 | 所有者のMacで `caffeinate -i ~/.chuck-deploy/bin/launch-retry.sh` を実行中。10分おき・最長36回（2026-10-17 01:48 UTCごろまで）、A1 1 OCPU・6GB、Canonical-Ubuntu-24.04-aarch64-2026.09.18-0、ブート50GB、公開IPなしで作成。成功時は `INST=` を `~/.chuck-deploy/oci-ids.env` に追記して終了。ログは `~/.chuck-deploy/launch-retry.log` |
| 再試行のユーザーデータ | CHUCKリポジトリにあった旧cloud-init（`docker.io` とCHUCKのクローン）。本リポジトリの `cloud-init.yaml` へは差し替えていない |
| ログイン | MacのOCI CLIはブラウザ・セッション（`oci session authenticate`）。`oci session refresh` で延長中。切れたら所有者のブラウザ・ログインが必要 |

Mac（所有者のMacBook Air、arm64）に置いたもの：

- SSH鍵 `~/.ssh/chuck_oci`
- CHUCKのBasic認証パスワード `~/.chuck-deploy/password` とハッシュ `password.bcrypt`（権限600）
- 各資源のOCID `~/.chuck-deploy/oci-ids.env`（リポジトリには入れない）
- OCI CLI 3.95.0（Homebrew）、`OCI_CLI_AUTH=security_token`、プロファイル DEFAULT
- 再試行スクリプト `~/.chuck-deploy/bin/launch-retry.sh`

MacにはGitHubの認証がない。GitHubへの書き込みはクラウド側のスレッドで行う。

## 3 VMができた後の手順

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
- 実VM上での起動、Let's Encryptの実証明書の取得は**未検証**。

## 5 関連

- CHUCK公開版：https://github.com/UeEmon/CHUCK-public-（公開版。設定は `docs/PUBLIC_DEPLOYMENT.md`、寄付は `docs/SPONSORS_SETUP.md`）
- CHUCK本家：https://github.com/UeEmon/VOCAP-COMPATIBILITY-（非公開。`docs/HANDOVER.md` にアプリ側の引き継ぎ）
- 要件ナビ：https://github.com/UeEmon/ai-requirements-navigator（公開イメージ `ghcr.io/ueemon/ai-requirements-navigator` はarm64対応）
- 無料枠の上限：A1合計4 OCPU・24GB、E2.1.Micro 2台、ブロック・ストレージ合計200GB、外向き通信 月10TB
