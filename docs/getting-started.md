# Getting Started — 管理PCからUbuntu対象PCを初期構築する

この手順は、新しい管理PC (ホスト名は`c0`固定になっています) をNixOS Minimal ISOから構築し、その管理PCを使って対象PC **k2** にUbuntu ServerをPXE経由でインストールするまでの、人手での作業をまとめたものです。既存ルーターがDHCPを配布し、両PCが同じ有線LANに接続している前提です。

> **データ消去に注意:** 管理PCの `install.sh` と対象PCのAutoinstallは、いずれもインストール先ディスクの内容を消去します。対象PCのPXE起動後は確認画面なしで初期化が始まります。

大まかな流れは次のとおりです。

1. 管理PCをNixOS Minimal ISOで起動
2. Minimal ISO上で本リポジトリの`install.sh`を取得し実行→管理PCがssh接続可能な状態で起動
3. 管理PC上で対象PCにインストールしたいISOをダウンロード
4. 管理PC上でPXEサーバ(Pixiecore)起動
5. 対象PCをネットワークブート→対象PCがssh接続可能な状態で起動

詳細は以下を参照ください。

## 1. 手元で用意するもの

- 管理PC (`c0`)：64GiBを超える内蔵ディスク1台、有線NIC1つ。USBからNixOS Minimal ISOを起動できること
- Ubuntu対象PC：Legacy BIOSのPXE起動が可能、有線LAN、初期化してよい内蔵ディスク1台、インストール用USBは接続しない
- 同じLANに接続するルーター：既存のDHCPをそのまま使う
- 管理・操作用端末： `ssh/authorized_keys` に対応する**秘密鍵**を持ち、`*.local` のmDNS解決ができること
- NixOS Minimal ISOを書き込んだ起動用USBメディア（管理PCの初回起動にのみ使用）

秘密鍵はリポジトリや対象PCのインストールデータには置きません。公開鍵は [ssh/authorized_keys](../ssh/authorized_keys) から読み込みます。

## 2. 管理PC c0をNixOS Minimal ISOで起動する

1. NixOS Minimal ISOをUSBメディアに書き込み、管理PCに接続する。
2. 管理PCをUSBから起動し、有線LANに接続する。
3. DHCPでネットワークが使えることを確認する。

```sh
ip -4 addr
ping -c 3 github.com
```

※ここでは起動用USBメディアを使いますが、`install.sh` はUSBをインストール対象に選びません。

## 3. 管理PCにNixOSをインストールする

Minimal ISO上で次を実行します。

```sh
curl -fL https://raw.githubusercontent.com/js4000all/ops-nixos-provisioner/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

`install.sh` はGitHubの `main` を取得し、ディスク、NIC、起動方式を検出してdiskoとNixOS Flakesでc0を構築します。**管理PCの内蔵ディスクの既存データは消去されます。**

終了したらUSBメディアを抜き、管理PCを内蔵ディスクから再起動します。

```sh
sudo reboot
```

## 4. c0へのSSH接続を確認する

管理・操作用端末から接続します。

```sh
ssh user1@c0.local
```

接続できない場合は、c0の有線接続とDHCP、操作端末のmDNS解決、公開鍵に対応する秘密鍵を確認します。

c0への接続後、構成を最新版へ更新する際は以下を使います。

```sh
cd /etc/nixos
sudo git pull --rebase
sudo nixos-rebuild dry-build --flake .#c0
sudo nixos-rebuild switch --flake .#c0
```

c0のハードウェア固有設定はローカルブランチ `c0-local` に保存され、GitHubにはpushしません。

## 5. c0でUbuntu ServerのPXE起動を準備する

Ubuntu Server 26.04.1 ISOを取得し、ISOからPXE用のカーネル・initrdを抽出します。ISOのダウンロードは初回に時間がかかります。

```sh
sudo systemctl start ubuntu-iso-fetch.service
sudo systemctl status ubuntu-iso-fetch.service

sudo systemctl start ubuntu-pxe-prepare.service
sudo systemctl status ubuntu-pxe-prepare.service

curl -I http://c0.local/ubuntu/ubuntu-26.04.1-live-server-amd64.iso
```

最後のHTTP応答で `200 OK` が返ることを確認します。これらの準備サービスは手動起動専用です。以前取得したISOと抽出済み起動ファイルがある場合、再利用されます。

## 6. 対象PCにUbuntu Serverを無人インストールする

1. **対象PC側:** デフォルトの起動順序が**内蔵ディスク優先**であることを確認する。起動時に手動選択できるLegacy BIOSのネットワークブートを有効にしておく。
2. **c0側:** インストール先のホスト名を指定して、Pixiecoreを起動する。下記の例は対象PCのホスト名を`k2`に設定する前提ですが、任意の名前を指定できます。

```sh
sudo ubuntu-autoinstall-select k2
sudo systemctl start ubuntu-pxe.service
systemctl status ubuntu-pxe.service
```

3. **対象PC側:** 電源を入れ、Boot Menuから**今回だけネットワーク起動**を選択する。
4. **待つ:** 対象PCがPXEでインストーラーを起動し、NoCloud設定を取得して内蔵ディスク全体を消去し、Ubuntuをインストールする。作業完了後は自動再起動し、内蔵ディスクから起動する。
5. **操作端末またはc0側:** mDNSホスト名でSSH接続する。

```sh
ssh user1@k2.local
```

初回起動後はUbuntu側の初期設定や時刻同期の完了までSSH接続できない場合があります。SSH接続ができれば、以下のように確認できます。

```sh
hostnamectl
timedatectl
systemctl is-active ssh avahi-daemon chrony
sudo -n true && echo "sudo OK"
```

最後にc0でPixiecoreを停止します。

```sh
sudo systemctl stop ubuntu-pxe.service
```

**重要:** 現在の仕組みは**1台ずつ**の手動運用です。PixiecoreとNoCloudシードはインストール完了時に自動停止・削除されません。PXEをデフォルト起動先にしていると、再起動後に同じディスクを再初期化する危険があります。次のPCをインストールするときは、新しいホスト名を `ubuntu-autoinstall-select` に渡して同様に実行します。

## 7. 問題が起きた場合の確認先

管理PCのログ：

```sh
journalctl -u ubuntu-iso-fetch.service -n 50
journalctl -u ubuntu-pxe-prepare.service -n 50
journalctl -u ubuntu-pxe.service -n 50
sudo tail -n 50 /var/log/nginx/access.log
```

NoCloudシードの公開内容：

```sh
curl -fsS http://c0.local/ubuntu/autoinstall/user-data
curl -fsS http://c0.local/ubuntu/autoinstall/meta-data
```

対象PCのインストーラーが対話画面で止まる場合は、`/proc/cmdline` に `autoinstall ds=nocloud-net;s=http://.../ubuntu/autoinstall/` があるかを確認します。ホスト名・鍵・SSHやNTPなどの詳細設定、Gitブランチの管理は [README](../README.md) を参照してください。
