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

`hardware-configuration.nix` は `nixos-generate-config --no-filesystems` で実機生成します。NIC名と起動方式・ディスクデバイスは `network-local.nix`、`boot-local.nix` に生成します。これらのファイルはGitHub上の共通ブランチではGit管理外ですが、インストール時に対象PC専用の `c0-local` ブランチへローカルコミットします。GitHubにはpushしません。

## 通常運用

インストール後、`ssh user1@c0.local` で公開鍵認証して接続できます。初期構築時に `/etc/nixos` の作業コピーには `c0-local` ブランチが作成され、生成された実機設定だけがコミットされています。上流は `origin/main` です。管理PC自身で次の操作を実行します。

```sh
cd /etc/nixos
sudo git status -sb
sudo git pull --rebase
sudo nixos-rebuild dry-build --flake .#c0
sudo nixos-rebuild switch --flake .#c0
```

`git pull --rebase` は `origin/main` の新しいコミットの上にローカル専用コミットを再適用します。ローカル設定はGit追跡済みなので通常のGit flake（`.#c0`）で評価できます。ローカルGit設定では `pull.rebase=true`、`push.default=nothing` に加えてpush先を無効なURLへ設定し、誤pushを防ぎます。ローカルコミットはGitHubには存在しないため、実機固有の完全なflake構成をGitHub上のコミットだけから再現することはできません。

rebaseが競合で停止した場合は競合を解消して `sudo git rebase --continue`、または `sudo git rebase --abort` を実行し、完了するまではrebuildしないでください。`git status` で未コミット変更が残っていないことを確認して更新します。通常の `nixos-rebuild switch` はディスクの再パーティション・フォーマットを行いません。ディスクを初期化するのはインストーラーでdiskoを明示実行したときだけです。

インストール時のcloneは `--no-single-branch` を指定するため、後からGitのブランチを切り替えられます。

## Ubuntu Server ISOの取得

PXE構築の準備として、Ubuntu Server 26.04.1 LTS (amd64) のISOを管理PC `c0` に保存できます。取得サービスは手動起動専用で、OS起動時・`nixos-rebuild switch` 時・定期タイマーでは実行されません。

設定反映後に以下を実行します。

```sh
sudo systemctl start ubuntu-iso-fetch.service
systemctl status ubuntu-iso-fetch.service
journalctl -u ubuntu-iso-fetch.service
```

ISOの保存先は `/var/lib/ubuntu-images/ubuntu-26.04.1-live-server-amd64.iso` です。URLとSHA256は `ubuntu-iso.nix` で固定し、[Ubuntu公式SHA256SUMS](https://releases.ubuntu.com/26.04.1/SHA256SUMS) と照合しています。

サービスを再実行すると、保存済みISOのSHA256を確認します。一致すればダウンロードを省略し、不一致または未取得の場合は再ダウンロードします。取得ファイルは検証成功後に配置します。ISOはNix StoreとGitの管理対象外です。

この段階ではISOを保存するだけで、PXE・HTTP配信・Autoinstallはまだ設定していません。

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
- `ubuntu-iso.nix`: Ubuntu Server ISOの手動取得・SHA256検証
- `hardware-configuration.nix` / `network-local.nix` / `boot-local.nix`: インストール時に生成し、実機専用のローカルGitコミットでのみ追跡する設定
- `docs/local-host-config.md`: ローカルブランチ運用上の制約と今後の検討課題
