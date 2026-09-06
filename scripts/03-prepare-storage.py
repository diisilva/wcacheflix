#!/usr/bin/env python3
"""03 - Prepara um disco dedicado para a mídia do wcacheflix.

Cria UMA partição EXT4 ocupando o disco inteiro, registra a montagem por UUID
em /etc/fstab (com 'nofail') e monta em /srv/wcacheflix.

É uma operação DESTRUTIVA: todo o conteúdo do disco escolhido é apagado.
Por segurança:
  * sem --apply o script só mostra o plano (dry-run), não altera nada;
  * recusa discos que contenham /, /boot, /boot/efi, swap, LVM/RAID/cripto
    ou qualquer partição montada;
  * exige confirmação digitando SIM (a menos que --yes seja passado).

Exemplos:
    # ver o plano, sem tocar em nada:
    sudo ./scripts/03-prepare-storage.py --disk /dev/sdb

    # aplicar de verdade:
    sudo ./scripts/03-prepare-storage.py --disk /dev/disk/by-id/ata-XXXX --apply

Dica: use um caminho estável de /dev/disk/by-id/ em vez de /dev/sdX.
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

FSTAB = Path("/etc/fstab")
FSTAB_BACKUP = Path("/etc/fstab.backup")
MOUNT_OPTS = "defaults,nofail,x-systemd.device-timeout=10s"
PROTECTED = ("/", "/boot", "/boot/efi", "/etc", "/usr", "/var", "/home")


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def fail(msg: str) -> "None":
    sys.exit(f"PARADA: {msg}")


def lsblk(disk: str) -> dict:
    data = json.loads(run(
        "lsblk", "-b", "-J", "-O", disk))["blockdevices"][0]
    return data


def maj_min_set(node: dict) -> set[str]:
    out = {node.get("maj:min")}
    for child in node.get("children", []) or []:
        out |= maj_min_set(child)
    return out


def inspect(disk: str) -> dict:
    real = str(Path(disk).resolve())
    if not Path(real).exists():
        fail(f"dispositivo não encontrado: {disk}")
    node = lsblk(real)
    if node.get("type") != "disk":
        fail(f"{disk} não é um disco inteiro (type={node.get('type')}). "
             "Aponte para o disco, não para uma partição.")
    if node.get("ro") in (True, "1", 1):
        fail(f"{disk} está somente-leitura.")

    disk_nums = maj_min_set(node)
    for target in PROTECTED:
        try:
            num = run("findmnt", "-n", "-o", "MAJ:MIN", "-T", target)
        except subprocess.CalledProcessError:
            continue
        if num in disk_nums:
            fail(f"{disk} contém '{target}' do sistema. Disco protegido.")

    def walk(n: dict):
        for m in (n.get("mountpoints") or []):
            if m:
                fail(f"{n.get('path')} está montado em {m}. Desmonte antes.")
        if n.get("type") == "part" and n.get("fstype") == "swap":
            fail(f"{n.get('path')} é swap ativa.")
        name = n.get("name")
        holders = Path("/sys/class/block") / name / "holders"
        if holders.is_dir() and any(holders.iterdir()):
            fail(f"{n.get('path')} tem dependentes (LVM/RAID/cripto). Não suportado.")
        for c in (n.get("children") or []):
            walk(c)
    walk(node)
    return node


def describe(node: dict) -> str:
    lines = [f"  {node.get('path')}  {node.get('model') or '?'}  "
             f"{int(node.get('size', 0)) / 1e9:.1f} GB  serial={node.get('serial') or '?'}"]
    for c in (node.get("children") or []):
        lines.append(f"    └─ {c.get('path')}  {int(c.get('size', 0)) / 1e9:.1f} GB  "
                     f"fs={c.get('fstype') or '-'}  label={c.get('label') or '-'}")
    if not node.get("children"):
        lines.append("    (sem partições)")
    return "\n".join(lines)


def ensure_fstab_entry(uuid: str, mount: str) -> bool:
    """Retorna True se a linha foi adicionada; False se já existia."""
    original = FSTAB.read_text()
    src = f"UUID={uuid}"
    for raw in original.splitlines():
        fields = raw.split("#", 1)[0].split()
        if len(fields) >= 2 and (fields[0] == src or fields[1] == mount):
            if fields[:2] != [src, mount]:
                fail(f"/etc/fstab já tem uma linha conflitante para {mount}: {raw!r}")
            return False
    if not FSTAB_BACKUP.exists():
        shutil.copy2(FSTAB, FSTAB_BACKUP)
    new = original.rstrip("\n") + f"\n\n# wcacheflix — mídia\n{src} {mount} ext4 {MOUNT_OPTS} 0 2\n"
    with tempfile.NamedTemporaryFile("w", dir="/etc", prefix=".fstab-wcx-", delete=False) as tf:
        tmp = Path(tf.name)
        os.fchmod(tf.fileno(), FSTAB.stat().st_mode & 0o777)
        tf.write(new)
        tf.flush()
        os.fsync(tf.fileno())
    os.replace(tmp, FSTAB)
    return True


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--disk", required=True, help="disco inteiro a preparar (ideal: /dev/disk/by-id/...)")
    p.add_argument("--mount", default="/srv/wcacheflix", help="ponto de montagem (padrão: /srv/wcacheflix)")
    p.add_argument("--label", default="WCACHEFLIX", help="rótulo EXT4 (padrão: WCACHEFLIX)")
    p.add_argument("--apply", action="store_true", help="executar de fato (sem isto é só dry-run)")
    p.add_argument("--yes", action="store_true", help="não pedir confirmação interativa")
    args = p.parse_args()

    for cmd in ("lsblk", "findmnt", "parted", "partprobe", "wipefs", "mkfs.ext4", "blkid", "udevadm"):
        if not shutil.which(cmd):
            fail(f"comando ausente: {cmd}")

    node = inspect(args.disk)
    real = str(Path(args.disk).resolve())

    print("Disco selecionado:")
    print(describe(node))
    print(f"\nPlano: apagar tudo, criar 1 partição EXT4 (label {args.label}) ocupando o disco,")
    print(f"       montar em {args.mount} e adicionar ao /etc/fstab por UUID (nofail).")

    if not args.apply:
        print("\n[dry-run] Nada foi alterado. Repita com --apply para executar.")
        return

    if os.geteuid() != 0:
        fail("execute com sudo.")
    if not args.yes:
        print(f"\n{'!' * 60}")
        print(f"TODO O CONTEÚDO DE {real} SERÁ PERDIDO.")
        print("!" * 60)
        if input("Digite SIM para confirmar: ").strip() != "SIM":
            fail("cancelado pelo usuário.")

    inspect(args.disk)  # revalida imediatamente antes de escrever

    print("\n==> Particionando")
    subprocess.run(["wipefs", "--all", real], check=True)
    subprocess.run(["parted", "--script", "--align", "optimal", real,
                    "mklabel", "gpt",
                    "mkpart", args.label, "ext4", "1MiB", "100%"], check=True)
    subprocess.run(["partprobe", real], check=True)
    subprocess.run(["udevadm", "settle", "--timeout=15"], check=True)

    # descobre o nó real da partição 1
    node = lsblk(real)
    children = node.get("children") or []
    if len(children) != 1:
        fail(f"esperava 1 partição após o particionamento, encontrei {len(children)}.")
    part = children[0]["path"]

    print(f"==> Formatando {part} como EXT4")
    subprocess.run(["wipefs", "--all", part], check=True)
    subprocess.run(["mkfs.ext4", "-m", "0", "-L", args.label, part],
                   check=True, stdin=subprocess.DEVNULL)

    uuid = run("blkid", "-p", "-s", "UUID", "-o", "value", part)
    print(f"==> UUID: {uuid}")

    Path(args.mount).mkdir(parents=True, exist_ok=True)
    added = ensure_fstab_entry(uuid, args.mount)
    print(f"==> /etc/fstab: {'linha adicionada' if added else 'já continha a montagem'} "
          f"(backup em {FSTAB_BACKUP})")

    subprocess.run(["systemctl", "daemon-reload"], check=True)
    subprocess.run(["mount", "-a"], check=True)

    mounted_uuid = run("findmnt", "-n", "-o", "UUID", "--mountpoint", args.mount)
    if mounted_uuid != uuid:
        fail(f"{args.mount} não montou o volume esperado (uuid montado: {mounted_uuid!r}).")

    print(run("findmnt", args.mount))
    print(run("df", "-hT", args.mount))
    print("\nOK. Agora rode:  ./scripts/04-create-layout.sh")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        sys.exit(f"PARADA: comando falhou ({exc}). Nada mais será feito.")
