# ペーパークラフトジェネレーター専用VM（papercraft-1）

ai-paper-modelar（UeEmon/ai-paper-modelar）を、SenroLab（Nine-Gage）とは別のVMで動かす構成です。
SenroLab の「再現してみた」の仮オブジェクトから、ペーパークラフトの展開図（実寸SVG）を作ります。API の仕様は ai-paper-modelar の `docs/senrolab/`。

**インターネットには公開しません。** SenroLab のVM（`ninegage-1`、サブネット 10.0.1.0/24）からだけ、VCN の中のプライベートIPで呼ばれます。利用者のブラウザは SenroLab にだけつながり、SenroLab のサーバーがこのVMを呼びます。

## 分離のしかた

- **VM**: `ninegage-1`・`chuck-1` とは別（`papercraft-1`）。
- **ネットワーク（Oracle）**: 専用のサブネット `papercraft-public` とセキュリティ・リスト `papercraft-sl`。受信できるのは TCP 8080 を `ninegage-public`（10.0.1.0/24）から、SSH を所有者のIPからだけ。80／443 は開けない。
- **ホストのファイアウォール**: `cloud-init.yaml` が 8080 を 10.0.1.0/24 からだけ許す（OCI の Ubuntu は SSH 以外を拒否するのが初期設定）。
- **コンテナ**: 8080 はこのVMのプライベートIPにだけ出す（公開IPでは応答しない）。読み取り専用・権限なし・メモリ512MB。
- **トークン**: `POST /v1/nets` は `PAPERCRAFT_API_TOKEN`（64文字の乱数）がないと 401。SenroLab に同じ値を持たせる。
- **イメージ**: VMではビルドしない。ai-paper-modelar の CI がテストと脆弱性検査を通した arm64 のイメージ（`:stable` = 最新のタグ `v*`）だけを動かす。

`bin/check-config.sh` が、ローカルビルド・余分なサービス・公開IPへのポート・トークンの欠落を止めます。

## Oracle Cloud で作るもの（所有者の操作、または所有者の指示でMacから）

無料枠（Ampere A1 は合計 4 OCPU・24GB、ブートボリュームは合計 200GB）の残りを先に確かめてください。いまは `chuck-1` と `ninegage-1` が 1 OCPU・6GB ずつ使っています。

| 資源 | 内容 |
|---|---|
| セキュリティ・リスト `papercraft-sl` | 受信: TCP 8080 は 10.0.1.0/24 だけ、TCP 22 は所有者のIP/32 だけ、ICMP 3/4。送信: すべて（イメージとこのリポジトリの取得に使う） |
| サブネット `papercraft-public` | VCN `chuck-vcn` の 10.0.2.0/24、ルート表は既存（インターネットゲートウェイ）、セキュリティ・リストは `papercraft-sl` だけ |
| VM `papercraft-1` | `VM.Standard.A1.Flex` 1 OCPU・6GB、Ubuntu 24.04 aarch64、ブート50GB、SSH鍵は `~/.ssh/chuck_oci`、ユーザーデータは `papercraft/cloud-init.yaml`。プライベートIPは 10.0.2.10 に固定すると設定が楽。公開IPは一時的なもの（予約しない）で、SSH と取得のためだけ |

`ninegage-sl` の送信はすべて許しているので、`ninegage-1` 側の変更は要りません。

## 初回の展開（papercraft-1 で）

```sh
cd ~/oracle-cloud-deploy/papercraft
cp env.example .env              # PAPERCRAFT_BIND_IP=10.0.2.10（このVMのプライベートIP）
bin/init-secrets.sh              # env/papercraft.env に PAPERCRAFT_API_TOKEN を作る
bin/check-config.sh
bin/up.sh
sudo cp systemd/papercraft-* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now papercraft-update.timer
curl -s http://10.0.2.10:8080/health   # {"ok":true}
```

イメージ `ghcr.io/ueemon/ai-paper-modelar` が非公開なら、GitHub の Packages で公開にするか、`docker login ghcr.io` しておきます。

## SenroLab につなぐ（ninegage-1 で）

`ninegage/env/ninegage.env` に2行足して `bin/up.sh` します。トークンは papercraft-1 の `env/papercraft.env` と同じ値です。

```sh
PAPERCRAFT_URL=http://10.0.2.10:8080
PAPERCRAFT_API_TOKEN=<papercraft-1 の値>
```

確かめ方: `docker compose exec nine-gage wget -qO- http://10.0.2.10:8080/health`。SenroLab で「再現してみた」の仮オブジェクトに「展開図」が出て、押すと印刷用の画面が開けば完了です。トークンは所有者のMacの `~/.chuck-deploy/papercraft/` に権限600で控えます。

ステージングにつなぐときは `env/ninegage-staging.env` に同じ2行を足します（つながなければ展開図のボタンは出ません）。

## 更新

`papercraft-update.timer` が5分ごとに、このリポジトリの `git pull` とイメージの取得を行い、何か変わっていれば `bin/check-config.sh` のあとに `bin/up.sh` します。本番に出すのは、ai-paper-modelar にタグ `v1.2.3` を付けたときだけです。急いで戻すときは `.env` に `PAPERCRAFT_TAG=1.2.2` と書いて `bin/up.sh` します。

データを持たないので、バックアップは要りません（作り直せば同じものが動きます）。
