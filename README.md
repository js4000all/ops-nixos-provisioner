# ops-nixos-provisioner

NixOSベースの管理PC構築用設定です。

## M1

NixOS Minimal ISO (UEFIまたはLegacy BIOS) から起動し、有線DHCPでネットワークに接続します。インストールスクリプトは対象ディスクの全内容を消去します。

```sh
curl -fL https://raw.githubusercontent.com/js4000all/ops-nixos-provisioner/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

```sh
curl -fL https://x.gd/S7bSj -o /tmp/install.sh
```

PRをmainにマージした後に上記を実行してください。

前提: インストール先は64GiB超の非USB・非リムーバブルディスクが1台、有線の物理NICが1台です。対象ディスク全領域をGPTで使用します。UEFIならESP 1GiB + ext4 rootとsystemd-boot、Legacy BIOSならBIOS boot 2MiB + ext4 rootとGRUBを使用します。

初回起動後は `ssh user1@c0.local` でSSH公開鍵認証し、 `/etc/nixos` で `sudo git pull --ff-only && sudo nixos-rebuild switch` を実行します。ハードウェア、NIC、ブートローダーの設定ファイル（`hardware-configuration.nix`、`network-local.nix`、`boot-local.nix`）は実機生成です。
