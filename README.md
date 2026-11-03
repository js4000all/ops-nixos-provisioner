# ops-nixos-provisioner

NixOSベースの管理PC `c0` の初期構築・運用設定です。OS構成はFlakesで、ディスク構成はdiskoで管理します。

## 初期構築

対象PCでNixOS Minimal ISOを起動し、有線LAN（DHCP）でネットワークに接続します。インストールには別の管理PCやNixツールを用意する必要はありません。

**注意: インストール先ディスクのパーティションとデータはすべて消去されます。**

```sh
curl -fL https://raw.githubusercontent.com/js4000all/ops-nixos-provisioner/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```
もしくは、
```sh
curl -fL https://x.gd/S7bSj -o /tmp/install.sh
```

`install.sh` は `main` のリポジトリを取得し、ロック済みの依存関係を利用してインストールします。事前に `flake.lock` がGitへコミットされている必要があります。

### 前提条件・処理内容

- 64GiB超の非USB・非リムーバブルなインストール対象ディスクが**ちょうど1台**
- 物理有線NICが**ちょうど1つ**
- 対象ディスク全体をGPTで初期化（暗号化・swapなし）
- UEFI: ESP 1GiB + ext4 root、systemd-boot
- Legacy BIOS: BIOS boot 2MiB + ext4 root、GRUB

スクリプトはディスク・NIC・起動方式を自動検出し、インストーラーが使用中のディスクと推定される場合には初期化を拒否します。diskoがパーティション作成・フォーマット・マウントを行い、その後 `nixos-install` でOSを導入します。パーティション作成は破壊的操作です。

`hardware-configuration.nix` は `nixos-generate-config --no-filesystems` で実機生成します。NIC名と起動方式・ディスクデバイスは `network-local.nix`、`boot-local.nix` に生成します。これらのファイルはGit管理外です。

## 通常運用

インストール後、`ssh user1@c0.local` で公開鍵認証して接続できます。管理PC自身で次の操作を実行します。

```sh
cd /etc/nixos
sudo git pull --ff-only
sudo nixos-rebuild dry-build --flake path:/etc/nixos#c0
sudo nixos-rebuild switch --flake path:/etc/nixos#c0
```

Git管理外の実機設定も評価できるよう、`path:/etc/nixos#c0` を指定します。通常の `nixos-rebuild switch` はディスクの再パーティション・フォーマットを行いません。ディスクを初期化するのはインストーラーでdiskoを明示実行したときだけです。

インストール時のcloneは `--no-single-branch` を指定するため、後からGitのブランチを切り替えられます。

## 依存バージョンの管理

`flake.nix` は `nixpkgs` と `disko` を定義し、`flake.lock` が使用リビジョンを固定します。依存関係を意図せず更新しないよう、ロックファイルもGit管理します。

GitHub Actionsの **Update flake.lock** を手動実行し、対象ブランチと操作を選択できます。

- `lock`: 既存のロックを基本的に維持しつつ、不足する入力を解決
- `update`: 依存入力を新しいリビジョンに更新

workflowは変更がある場合に限って、選択したブランチへ `flake.lock` をコミットします。依存更新後は差分とNixOSのビルド・動作を確認してから適用してください。

## 構成ファイル

- `flake.nix` / `flake.lock`: NixOS構成のエントリーポイントと依存固定
- `configuration.nix`: SSH、mDNS、WoL、ブートローダーなどのOS設定
- `disk-config.nix`: diskoのディスク宣言とファイルシステムのマウント設定
- `install.sh`: 初期構築の実行制御と実機固有情報の生成
- `hardware-configuration.nix` / `network-local.nix` / `boot-local.nix`: インストール時に生成するGit管理外の実機設定
