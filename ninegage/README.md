# Nine-Gage 専用VM

Nine-Gage（UeEmon/Nine-Gage-Systems）を、CHUCKなどと別のVMで動かす構成です。入口のCaddy、本番、ステージング、ペーパークラフトジェネレーター、ターミナル（旧称「みんなのレイアウト」を動かします。

| サイト | URL | ログイン |
|---|---|---|
| 本番（最新のリリース `v*` = イメージ `:stable`） | `https://<NINEGAGE_DOMAIN>` | Nine-Gage自身のログイン |
| ステージング（mainの最新 = `:main`） | `https://staging.<NINEGAGE_DOMAIN>` | Caddyのパスワード（`env/staging-auth.env`、ユーザー名 `staging`）と、ステージング自身のログイン |
| ターミナル（レイアウトの共有。最新のリリース = `ghcr.io/ueemon/nine-gage-terminal:stable`） | `https://terminal.<NINEGAGE_DOMAIN>` | 見るのはだれでも。投稿は本番の SenroLab のアカウント（本番がログインを確かめて渡す） |

`NINEGAGE_DOMAIN` は、独自ドメインを取るまでは、このVMの予約済み公開IPのドットをハイフンにした `<IP>.sslip.io` です。ドメインを取ったら `.env` の `NINEGAGE_DOMAIN` を変えて `bin/up.sh` するだけで移れます（DNSのAレコードをこのVMのIPに向けておく）。

## 分離のしかた

- **VM**: CHUCK・要件ナビ・BACCHUS・海日和とは別のVM（`ninegage-1`）。CPU・メモリ・Dockerを共有しない。
- **ネットワーク（Oracle）**: 専用のサブネット `ninegage-public` とセキュリティ・リスト `ninegage-sl`。外から開けるのは TCP 80／443 と UDP 443 だけ。SSHは所有者のIPからだけ。
- **ネットワーク（Docker）**: 本番は `prod-edge`、ステージングは `staging-edge` にだけつながり、相手はCaddyだけ。本番とステージングは互いに届かない。
- **秘密**: 本番とステージングで別の値（`env/ninegage.env` と `env/ninegage-staging.env`）。
- **イメージ**: VMではビルドしない。CIがテストと脆弱性検査を通したイメージだけを動かす。

`bin/check-config.sh` が、ローカルビルド・余分なサービス・ポートの公開・ネットワークの共有・秘密の欠落を止めます。

## Oracle Cloudで作るもの（所有者の操作、または所有者の指示でMacから）

| 資源 | 内容 |
|---|---|
| サブネット `ninegage-public` | VCN `chuck-vcn` の 10.0.1.0/24、公開、ルート表は既存（インターネットゲートウェイ） |
| セキュリティ・リスト `ninegage-sl` | 受信: TCP 80／443・UDP 443 は 0.0.0.0/0、TCP 22 は所有者のIP/32 だけ、ICMP 3/4。送信: すべて |
| VM `ninegage-1` | `VM.Standard.A1.Flex` 1 OCPU・6GB、Ubuntu 24.04 aarch64、ブート50GB、SSH鍵は `~/.ssh/chuck_oci`、ユーザーデータはこのリポジトリの `cloud-init.yaml` |
| 予約済み公開IP `ninegage-ip` | `ninegage-1` に割り当てる |
| 動的グループ `ninegage-backup` | `ninegage-1` だけ（`instance.id = '<OCID>'`） |
| ポリシー `ninegage-backup` | `Allow dynamic-group ninegage-backup to manage objects in tenancy where target.bucket.name='chuck-backups'` |

## 初回の展開（VMで）

```sh
cd ~/oracle-cloud-deploy/ninegage
cp env.example .env              # NINEGAGE_DOMAIN=<IPのハイフン区切り>.sslip.io
bin/init-secrets.sh              # 本番・ステージング・Caddyのパスワードを乱数で作る
bin/check-config.sh
bin/up.sh
sudo cp systemd/ninegage-* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now ninegage-update.timer ninegage-backup.timer
```

作られた `env/ninegage.env` の `NINEGAGE_SECRET_KEY` と `NINEGAGE_BACKUP_KEY` は、所有者のMacの `~/.chuck-deploy/ninegage/` に権限600で控えます。どちらかを失うと、バックアップから戻したときに保存済みのAPIキーやバックアップそのものが読めません。

## CHUCKのVMからの移行

CHUCKのVM（`chuck-1`）で動いている本番のユーザーとAI設定を、そのまま移します。移す間（数分）は本番が止まります。

1. 新しいVMで、上の「初回の展開」の `bin/init-secrets.sh` の**前に**、`chuck-1` の `env/ninegage.env` をコピーする（同じ管理者・同じ `NINEGAGE_SECRET_KEY` で、保存済みのAPIキーが読める）。そのあと `bin/init-secrets.sh` が `NINEGAGE_BACKUP_KEY` を足す。
2. `chuck-1` で本番を止めて、データを書き出す。
   ```sh
   cd ~/oracle-cloud-deploy && docker compose stop nine-gage
   docker run --rm -v oracle-cloud-deploy_ninegage-data:/d:ro alpine tar czf - -C /d . > ninegage-data.tar.gz
   ```
3. ファイルを新しいVMに運び（Mac経由の `scp`）、新しいVMで取り込んでから起動する。
   ```sh
   cd ~/oracle-cloud-deploy/ninegage
   docker compose create nine-gage
   docker run --rm -i -v ninegage_ninegage-data:/d alpine sh -c 'tar xzf - -C /d && chown -R 1000:1000 /d' < ninegage-data.tar.gz
   bin/up.sh
   ```
   以前の `store.json` は、起動時に `store.sqlite` へ取り込まれ、`store.json.migrated` に名前が変わる。
4. 新しいURLでログインできること、ユーザーがそろっていることを確かめる。
5. `chuck-1` 側で、Nine-Gageのサービスを外し、`nine-gage.<CHUCKのドメイン>` を新しいURLへ転送する（別のPRで行う）。運んだ `ninegage-data.tar.gz` は確かめたら消す。

## バックアップ

`ninegage-backup.timer` が毎日3:30（JST）ごろに `bin/backup.sh` を動かします。アプリの `scripts/backup.mjs` がSQLiteの一貫した写しを取り、`NINEGAGE_BACKUP_KEY` で暗号化したものを、Object Storageの `chuck-backups/ninegage/<日時>/ninegage.ngbak` に置きます。`BACKUP_KEEP_DAYS`（既定14日）より古いものは消えます。ステージングは対象外です。

戻すときは、ファイルを取り出し、アプリのリポジトリで次を実行します。

```sh
NINEGAGE_BACKUP_KEY=<控えた鍵> node scripts/restore-backup.mjs ninegage.ngbak store.sqlite
```

できた `store.sqlite` は、本番を止めてから、ボリューム `ninegage_ninegage-data` の `store.sqlite` と置き換えます（`store.sqlite-wal` と `-shm` は消す）。月に一度は、ステージングに戻して開けるかを試してください。

## 更新

`ninegage-update.timer` が5分ごとに、このリポジトリの `git pull` とイメージの取得を行い、何か変わっていれば `bin/check-config.sh` のあとに `bin/up.sh` します。本番に出すのは、Nine-Gage-Systemsにタグ `v1.2.3` を付けたときだけです。急いで戻すときは `.env` に `NINEGAGE_TAG=1.2.2` と書いて `bin/up.sh` します。

## 死活確認

Nine-Gage-Systemsのリポジトリ変数 `NINEGAGE_HEALTH_URL` に `https://<NINEGAGE_DOMAIN>/api/health` を設定すると、GitHub Actionsが15分ごとに確かめ、応答がなければ所有者にメールが届きます。

## 改善リクエストの GitHub 連携

利用者がアプリの「改善リクエスト」から送った内容を、Nine-Gage-Systems の Issue にします（アプリ側の説明は Nine-Gage-Systems の README「改善リクエスト」）。トークンがなければ、管理画面に保存するだけです。

1. GitHub の [Fine-grained personal access tokens](https://github.com/settings/personal-access-tokens/new) で、Repository access を「Only select repositories → UeEmon/Nine-Gage-Systems」、Permissions を「Issues: Read and write」だけにして作る（有効期限は1年など。切れたら作り直す）。
2. VMで `env/ninegage.env` に `NINEGAGE_FEEDBACK_GITHUB_TOKEN=<トークン>` を足し、`bin/up.sh`。本番だけに入れ、ステージングには入れない（試しの送信が公開の Issue にならないように）。
3. トークンの値は所有者のMacの `~/.chuck-deploy/ninegage/` にも控える。

確かめ方: 本番で「改善リクエスト」から1件送り、`改善リクエスト` ラベルの Issue ができること。失敗したときは管理画面の「改善リクエスト」に理由が出て、「Issue にする」で登録し直せます。

## ペーパークラフトジェネレーター

「再現してみた」の仮オブジェクトを展開図にするジェネレーター（UeEmon/ai-paper-modelar）は、2026-11-16にVM `papercraft-1` からこのVMの別コンテナ `papercraft` へ移しました。イメージはCIの `ghcr.io/ueemon/ai-paper-modelar:stable`（`.env` の `PAPERCRAFT_TAG` で戻せる）で、メモリ512MB・0.75 CPUに制限しています。

- ホストのポートは開けず、インターネットからもCaddyからも届きません。専用のDockerネットワーク `papercraft` を本番の `nine-gage` とだけ共有し、ステージングからも届きません。
- 本番の `nine-gage` は `PAPERCRAFT_URL=http://papercraft:8086`（`compose.yaml` で固定）で呼び、トークンは両方とも `env/papercraft.env` の `PAPERCRAFT_API_TOKEN` を読みます。`bin/init-secrets.sh` がなければ作ります。`env/ninegage.env` に古い `PAPERCRAFT_URL`・`PAPERCRAFT_API_TOKEN` が残っていても、こちらが優先されます。
- `bin/check-config.sh` が、ローカルビルド・ホストのポート・ネットワークの共有範囲・トークンの不一致を止めます。

確かめ方: `docker compose exec nine-gage wget -qO- http://papercraft:8086/health` が `{"ok":true}`。SenroLab の仮オブジェクトに「展開図」が出て、押すと印刷用の画面が開けば完了です。

## ターミナル（レイアウトの共有）

レイアウトを投稿・共有し、投稿どうしをボードの端の線路でつなぐサイト（Nine-Gage-Systems の `terminal/`、[terminal/README.md](https://github.com/UeEmon/Nine-Gage-Systems/blob/main/terminal/README.md)）を、2026-11-18に別コンテナ `terminal` として加えました。イメージはCIの `ghcr.io/ueemon/nine-gage-terminal:stable`（プラットフォームと同じく、タグ `v*` を付けたときに作られる。`.env` の `TERMINAL_TAG` で戻せる）で、メモリ384MB・0.5 CPUに制限しています。

- 専用のDockerネットワーク `terminal-edge` をCaddyとだけ共有し、本番・ステージング・ペーパークラフトには届きません。ホストのポートも開けません。
- データはボリューム `ninegage_share-data`（改名前の名前のまま。compose では `terminal-data`）の `terminal.sqlite`（改名前の `share.sqlite` は、ターミナルが起動時に名前を変える）。毎日のバックアップで `terminal.sqlite` として一緒に置きます（中身は公開の投稿と SenroLab のユーザー名だけなので暗号化はしない）。
- ログインはパスワードを持たず、本番が署名した合図で受け取ります。鍵は `env/terminal-link.env` の `SENROLAB_TERMINAL_SECRET`（本番とターミナルの両方が読む）と、ターミナルだけの `env/terminal.env` の `TERMINAL_SESSION_SECRET`。どちらも `bin/init-secrets.sh` がなければ作ります（自動更新でも呼ばれる）。ステージングには渡しません。
- 本番の `SENROLAB_TERMINAL_URL`（`https://terminal.<NINEGAGE_DOMAIN>`）と、ターミナルの `SENROLAB_URL`（`https://<NINEGAGE_DOMAIN>`）は `compose.yaml` で固定し、`bin/check-config.sh` が確かめます。

**改名（2026-11-24、share → terminal）**: サービス `share`・イメージ `nine-gage-share`・`share.<NINEGAGE_DOMAIN>` を、`terminal`・`nine-gage-terminal`・`terminal.<NINEGAGE_DOMAIN>` に変えました。`share.<NINEGAGE_DOMAIN>` は Caddy が `terminal.<NINEGAGE_DOMAIN>` へ転送します。`bin/init-secrets.sh` は `env/share.env`・`env/share-link.env` の値を引き継いで `env/terminal.env`・`env/terminal-link.env` を作るので、鍵は変わりません（古いファイルは消さずに残ります）。ブラウザのログインの Cookie はホスト名ごとなので、ターミナルには一度ログインし直しになります。

**初めて出すときの順番**: `nine-gage-terminal:stable` のイメージがないうちにこの構成を main に入れると、自動更新の `docker compose pull` が失敗して、本番の更新まで止まります。先に Nine-Gage-Systems の変更をマージしてタグ `v*` を付け、Actions でイメージができたら、GitHub のパッケージ `nine-gage-terminal` の公開範囲を Public にしてから（プラットフォームの `nine-gage-systems` と同じ）、この構成をマージしてください。

確かめ方: `https://terminal.<NINEGAGE_DOMAIN>/api/health` が `{"ok":true}`。本番の画面右上の「ターミナル」からターミナルに移り、「SenroLabのアカウントでログイン」で本番のログインを経て戻ってくれば完了です。
