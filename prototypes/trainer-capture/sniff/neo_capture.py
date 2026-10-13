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
import pathlib
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

    def handler(char, data):
        now = dt.datetime.now(dt.timezone.utc)
        name = label(char.uuid)
        w.writerow([now.isoformat(timespec="milliseconds"), f"{(now - start).total_seconds():.3f}",
                    name, " ".join(f"{x:02X}" for x in data)])
        counts[name] = counts.get(name, 0) + 1
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
                print("Lance ou continue ta séance. Ctrl+C pour arrêter.\n")
                while client.is_connected:
                    await asyncio.sleep(1)
                    f.flush()
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
    args = p.parse_args()
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        pass
    print("\nArrêté. Fichier enregistré à côté du programme (capture-….csv).")


if __name__ == "__main__":
    main()
