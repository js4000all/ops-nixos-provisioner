# ops-nixos-provisioner

NixOSベースの管理PC構築用設定です。

## M1

NixOS Minimal ISO (UEFI) から起動し、有線DHCPでネットワークに接続します。インストールスクリプトは対象ディスクの全内容を消去します。

```sh
curl -fL https://raw.githubusercontent.com/js4000all/ops-nixos-provisioner/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

PRをmainにマージした後に上記を実行してください。

前提: インストール先は64GiB超の非USB・非リムーバブルディスクが1台、有線の物理NICが1台です。SSD全領域をGPT (ESP 1GiB、残りext4 root)で使用します。

初回起動後は `ssh user1@c0.local` でSSH公開鍵認証し、 `/etc/nixos` で `sudo git pull --ff-only && sudo nixos-rebuild switch` を実行します。ハードウェアとNICの設定ファイルは実機生成です。
