# ops-nixos-provisioner

NixOSベースの管理PC構築用設定です。

## M1: Flakes + disko 実機検証用ブランチ

NixOS Minimal ISO（UEFIまたはLegacy BIOS）から起動し、有線DHCPでネットワークへ接続します。**インストール先ディスクの全内容が消去されます。**

このPRの実機検証中は **mainのinstall.shを使わず**、作業ブランチのスクリプトを取得してください。

```sh
curl -fL https://raw.githubusercontent.com/js4000all/ops-nixos-provisioner/feat/flake-disko-bootstrap/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

開始前にGitHub Actionsの `Update flake.lock` を **feat/flake-disko-bootstrap** ブランチに対して手動実行し、`flake.lock` が同ブランチへコミットされたことを確認してください。lockファイルがなければインストール処理はディスク消去前に停止します。

前提条件は従来と同じです。インストール先は64GiB超の非USB・非リムーバブルディスクが1台、有線の物理NICが1台です。全容量をGPTとして使用し、UEFIではESP 1GiB + ext4 rootとsystemd-boot、Legacy BIOSではBIOS boot 2MiB + ext4 rootとGRUBを使います。

- `flake.nix` がNixOS構成とdiskoのロックされた依存を定義します。
- `disk-config.nix` がパーティション、フォーマット、マウントおよびNixOSの `fileSystems` を宣言します。
- `install.sh` はディスクとNICの安全確認、実機設定の生成、disko実行、`nixos-install` に集中します。
- `hardware-configuration.nix` は `nixos-generate-config --no-filesystems` で実機生成します。
- `network-local.nix` と `boot-local.nix` はGit管理外です。ローカル生成ファイルをFlake評価へ含めるため、`path:` を明示します。

起動後は `ssh user1@c0.local` で接続できます。通常の再構築には次のコマンドを使います。

```sh
cd /etc/nixos
sudo git pull --ff-only
sudo nixos-rebuild dry-build --flake path:/etc/nixos#c0
sudo nixos-rebuild switch --flake path:/etc/nixos#c0
```

**注意:** 実機検証中は `/etc/nixos` のGitブランチも作業ブランチです。mainへマージするまではmainへ切り替えないでください。通常の`nixos-rebuild switch`はdiskoによるディスク再初期化を実行しません。
