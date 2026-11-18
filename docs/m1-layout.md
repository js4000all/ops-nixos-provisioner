# M1: 管理PC・プロビジョニング基盤・ワーカーの責務分離

## 第一段階のスコープ

- 管理PC自身の静的NixOS構成を `controller/` に置く。
- UbuntuのISO取得、PXE、HTTP配信、Autoinstallのモジュールを `provisioner/ubuntu/` に置く。
- `worker/` は将来のAnsible/NixOSワーカー構成の格納場所として定義する。最初のAnsible roleは次段階で実装する。
- Python 3とAnsibleは管理PCのNixOS構成から導入する。Python製 `provision` CLIは後続段階で実装する。

## 互換性

- 公開済みの `install.sh` URLは変更しない。
- `flake.nix` の公開出力 `nixosConfigurations.c0` と `packages.x86_64-linux.disko` は変更しない。
- 実機生成される3つの `*-local.nix` / `hardware-configuration.nix` は引き続きリポジトリ直下に配置し、`c0-local` ローカルブランチで追跡する。
- Ubuntu用サービス・コマンド名、NoCloudのHTTPパス、ISOのURL・SHA256、PXE動作は変更しない。
- 設定ファイルの移動に伴う相対パスは更新する。

## 検証

- `nix flake show` / `sudo nixos-rebuild dry-build --flake .#c0`（実機生成ファイルがある管理PC上で実行）。
- `sudo nixos-rebuild switch --flake .#c0` 実行後、`python3 --version` と `ansible --version`。
- 従来どおりの `ubuntu-iso-fetch.service` / `ubuntu-pxe-prepare.service` / `ubuntu-pxe.service` の起動とNoCloudシード配信。
- 新規管理PCのMinimal ISOからの `install.sh` 完走。

実機検証前にPRをマージしない。特にNixOSの評価・インストールはGitHub上の静的レビューでは代替できない。
