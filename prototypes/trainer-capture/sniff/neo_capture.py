#!/usr/bin/env python3
"""
Enregistre tout ce que le home-trainer publie en Bluetooth, depuis le Mac ou le PC.

Pendant une séance où l'app indoor (MyWhoosh…) pilote le home-trainer en ANT+ FE-C, la
connexion Bluetooth du home-trainer est libre : ce programme la prend, s'abonne à tout ce qui
peut se lire, et écrit chaque notification, octets bruts compris, dans un CSV. Il ne donne
aucune consigne au home-trainer.

    python3 neo_capture.py              cherche un appareil dont le nom contient « Neo »
    python3 neo_capture.py --list       liste les appareils Bluetooth à portée, puis s'arrête
    python3 neo_capture.py --name KICKR un autre home-trainer

Ctrl+C pour arrêter. Le fichier capture-<date>.csv est écrit à côté du programme.

Le Neo n'accepte qu'une connexion Bluetooth : DS ne doit pas être connecté au Neo en même temps.
"""
import argparse
import asyncio
import csv
import datetime as dt
import os
import pathlib
import subprocess
import sys

from bleak import BleakClient, BleakScanner

BASE = "-0000-1000-8000-00805f9b34fb"


def full(short):
    return f"0000{short.lower()}{BASE}"


# Ce qu'on cherche en priorité ; tout le reste qui se lit en notification est pris aussi.
KNOWN = {
    full("2A63"): "2A63",   # Cycling Power Measurement
    full("2AD2"): "2AD2",   # FTMS Indoor Bike Data
    full("2ADA"): "2ADA",   # FTMS Fitness Machine Status
    full("2A5B"): "2A5B",   # CSC Measurement
    full("2A37"): "2A37",   # Heart Rate Measurement
    "6e40fec2-b5a3-f393-e0a9-e50e24dcca9e": "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E",  # FE-C de Tacx
}
# Jamais d'abonnement sur un point de contrôle : on écoute, on ne commande pas.
NEVER = {full("2AD9"), full("2A66"), "6e40fec3-b5a3-f393-e0a9-e50e24dcca9e"}
FEC_WRITE = "6e40fec3-b5a3-f393-e0a9-e50e24dcca9e"


def page71_request(channel=5):
    """Message ANT « envoie-moi ta page 71 » (FE-C page 70, Request Data Page).

    Ce n'est PAS une consigne de résistance : le home-trainer répond seulement en publiant la page 71
    (Command Status), qui contient la dernière commande reçue — la pente que l'app indoor lui a
    envoyée en ANT+. Format : A4 · longueur · 4F (acquitté) · canal · 8 octets de page · contrôle XOR.
    """
    page = [0x46, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x47, 0x01]
    msg = [0xA4, 0x09, 0x4F, channel] + page
    x = 0
    for b in msg:
        x ^= b
    return bytes(msg + [x])


def label(uuid):
    u = uuid.lower()
    if u in KNOWN:
        return KNOWN[u]
    if u.startswith("0000") and u.endswith(BASE):
        return u[4:8].upper()
    return u.upper()


def live_summary(name, data):
    """Un aperçu à l'écran, pour voir que ça tourne. Le décodage complet se fait après."""
    b = bytes(data)
    try:
        if name == "2A63" and len(b) >= 4:
            return f"{int.from_bytes(b[2:4], 'little', signed=True)} W"
        if name == "2AD2" and len(b) >= 4 and not (b[0] & 1):
            return f"{int.from_bytes(b[2:4], 'little') / 100:.1f} km/h"
        if name == "2ADA" and b[:1] == b"\x12" and len(b) >= 5:
            return f"pente {int.from_bytes(b[3:5], 'little', signed=True) / 100:.1f} %"
        if name.startswith("6E40FEC2") and len(b) >= 12 and b[0] == 0xA4:
            page = b[4:12]
            if page[0] == 0x10:                                  # page 16 : vitesse
                return f"{int.from_bytes(page[4:6], 'little') / 1000 * 3.6:.1f} km/h (FE-C)"
            if page[0] == 0x47 and page[1] == 0x33:              # page 71 → dernière page 51
                raw = int.from_bytes(page[5:7], "little")
                if raw != 0xFFFF:
                    return f"pente {raw / 100 - 200:.1f} % (consigne)"
            if page[0] == 0x47:
                return f"page 71 : dernière commande {page[1]:02X}"
    except Exception:
        pass
    return ""


async def find(name, timeout):
    print(f"Recherche d'un appareil dont le nom contient « {name} »…")
    devices = await BleakScanner.discover(timeout=timeout)
    for d in devices:
        if d.name and name.lower() in d.name.lower():
            return d
    return None


async def run(args):
    if args.list:
        for d in await BleakScanner.discover(timeout=args.timeout):
            print(f"{d.address}  {d.name or '(sans nom)'}")
        return

    device = await find(args.name, args.timeout)
    if device is None:
        sys.exit(f"Aucun appareil « {args.name} » trouvé. Réveille le home-trainer (pédale un tour), "
                 "vérifie que DS n'y est pas connecté, ou essaie --list.")
    print(f"Trouvé : {device.name}")

    start = dt.datetime.now(dt.timezone.utc)
    out = pathlib.Path(__file__).resolve().parent / f"capture-{start.strftime('%Y-%m-%dT%H-%M-%S')}.csv"
    f = open(out, "w", newline="", encoding="utf-8")
    w = csv.writer(f)
    w.writerow(["heure", "t_s", "caracteristique", "brut"])
    counts = {}
    fec_channel = [5]       # le canal ANT vu dans les messages du Neo, pour lui répondre sur le même

    def handler(char, data):
        now = dt.datetime.now(dt.timezone.utc)
        name = label(char.uuid)
        w.writerow([now.isoformat(timespec="milliseconds"), f"{(now - start).total_seconds():.3f}",
                    name, " ".join(f"{x:02X}" for x in data)])
        counts[name] = counts.get(name, 0) + 1
        if name.startswith("6E40FEC2") and len(data) >= 4 and data[0] == 0xA4:
            fec_channel[0] = data[3]
        s = live_summary(name, data)
        if s:
            print(f"\r{name}: {s:<14}  ({sum(counts.values())} messages)", end="", flush=True)

    stop = asyncio.Event()
    while not stop.is_set():
        try:
            async with BleakClient(device, disconnected_callback=lambda _: print("\n⚠ Connexion perdue, je réessaie…")) as client:
                print("Connecté. Services et caractéristiques :")
                subscribed = []
                for service in client.services:
                    print(f"  service {label(service.uuid)}")
                    for ch in service.characteristics:
                        props = ",".join(ch.properties)
                        print(f"    {label(ch.uuid):<38} {props}")
                        if ch.uuid.lower() in NEVER:
                            continue
                        if "notify" in ch.properties or "indicate" in ch.properties:
                            try:
                                await client.start_notify(ch, handler)
                                subscribed.append(label(ch.uuid))
                            except Exception as e:
                                print(f"      (abonnement refusé : {e})")
                print(f"Écoute de : {', '.join(subscribed)}")
                can_ask = args.fec_status and any(
                    ch.uuid.lower() == FEC_WRITE for sv in client.services for ch in sv.characteristics)
                if args.fec_status and not can_ask:
                    print("(pas de canal FE-C Tacx en écriture : la pente ne sera pas demandée)")
                elif can_ask:
                    print(f"Pente : demande de la page 71 toutes les {args.fec_interval:g} s (aucune consigne envoyée).")
                print("Lance ou continue ta séance. Ctrl+C pour arrêter.\n")
                last_ask, failures = 0.0, 0
                while client.is_connected:
                    await asyncio.sleep(1)
                    f.flush()
                    now = asyncio.get_running_loop().time()
                    if can_ask and failures < 3 and now - last_ask >= args.fec_interval:
                        last_ask = now
                        msg = page71_request(fec_channel[0])
                        try:
                            await client.write_gatt_char(FEC_WRITE, msg, response=False)
                            failures = 0
                            t = dt.datetime.now(dt.timezone.utc)
                            w.writerow([t.isoformat(timespec="milliseconds"),
                                        f"{(t - start).total_seconds():.3f}", "->6E40FEC3",
                                        " ".join(f"{x:02X}" for x in msg)])
                        except Exception as e:
                            failures += 1
                            print(f"\n(demande de page 71 refusée : {e})")
                            if failures >= 3:
                                print("Trois refus de suite : je n'insiste plus, la capture continue.")
        except asyncio.CancelledError:
            break
        except Exception as e:
            print(f"\n⚠ {e} — nouvelle tentative dans 3 s")
            await asyncio.sleep(3)

    f.close()


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--name", default="Neo", help="partie du nom Bluetooth du home-trainer (défaut : Neo)")
    p.add_argument("--list", action="store_true", help="lister les appareils à portée et s'arrêter")
    p.add_argument("--timeout", type=float, default=10, help="durée de la recherche, en secondes")
    p.add_argument("--fec-status", action="store_true",
                   help="demander régulièrement au Neo sa page 71 FE-C (la pente reçue de l'app indoor)")
    p.add_argument("--fec-interval", type=float, default=5, help="intervalle de ces demandes, en secondes")
    args = p.parse_args()
    # Le Mac reste éveillé tant que ce programme tourne. caffeinate est lancé À CÔTÉ, pas devant :
    # lancé par `caffeinate python…`, le programme voyait macOS lui refuser le Bluetooth, même
    # avec le Terminal autorisé — la demande était imputée à caffeinate.
    if sys.platform == "darwin" and not args.list:
        try:
            subprocess.Popen(["caffeinate", "-di", "-w", str(os.getpid())])
        except OSError:
            pass
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        pass
    except Exception as e:
        if "not authorized" in str(e).lower() or "unauthorized" in str(e).lower():
            sys.exit("\nLe Terminal n'a pas le droit d'utiliser le Bluetooth.\n"
                     "Réglages Système › Confidentialité et sécurité › Bluetooth : activer Terminal\n"
                     "(bouton + si absent, dans Applications › Utilitaires), puis quitter le Terminal (⌘Q)\n"
                     "et relancer Neo Capture.")
        if "powered off" in str(e).lower() or "turned off" in str(e).lower():
            sys.exit("\nLe Bluetooth du Mac est éteint : l'allumer, puis relancer Neo Capture.")
        raise
    print("\nArrêté. Fichier enregistré à côté du programme (capture-….csv).")


if __name__ == "__main__":
    main()
