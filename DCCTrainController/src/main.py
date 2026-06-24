"""
DCC Train Layout Controller — main entry point.

Usage:
    python -m src.main                           # interactive menu
    python -m src.main --config config/layout.yaml
    python -m src.main --web                     # launch browser dashboard
"""

from __future__ import annotations
import argparse
import asyncio
import logging
import os
import sys

from .cs3_client import CS3PlusClient
from .layout import load_layout
from .automation import AutomationEngine
from .notify import notify

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s — %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("main")


async def _scan_locos(cs3: CS3PlusClient):
    """
    Ask the CS3+ for every loco it knows about and print a table.
    MFX locos appear automatically once placed on the track.
    DCC locos appear after you add them in the CS3+ loco database.
    Use the address shown here when setting dcc_address in layout.yaml.
    """
    print("\n  Scanning CS3+ for registered locomotives…")
    locos = await cs3.discover_locos()
    if not locos:
        print("  No locos found. Make sure MFX locos are on the track and powered.")
        return

    print(f"\n  {'#':<4} {'Name':<25} {'Protocol':<8} {'Address':<10} {'Speed':<7} Dir")
    print("  " + "-" * 62)
    for i, loco in enumerate(locos, 1):
        name     = loco.get("name", "—")[:24]
        protocol = loco.get("protocol", "?").upper()
        address  = loco.get("address", loco.get("id", "?"))
        speed    = loco.get("speed", 0)
        direction = "FWD" if loco.get("direction", 1) else "REV"
        print(f"  {i:<4} {name:<25} {protocol:<8} {str(address):<10} {speed:<7} {direction}")

    print(f"\n  Total: {len(locos)} loco(s)")
    print("  Add the address and protocol to config/layout.yaml for each loco you want to automate.")
    print("  MFX locos: use the address shown above (assigned by CS3+ on first registration).")
    print("  DCC locos: use the DCC address you programmed on CV1 (avoid address 3).")


async def interactive_menu(engine: AutomationEngine, cs3: CS3PlusClient, layout):
    print("\n" + "=" * 55)
    print("  DCC Train Layout Controller")
    print("  Märklin CS3+ Connected")
    print("=" * 55)

    while True:
        print("\n  [1] Start automatic operation (all trains)")
        print("  [2] Stop all trains (emergency stop)")
        print("  [3] Resume after emergency stop")
        print("  [4] Set individual loco speed")
        print("  [5] Control a signal manually")
        print("  [6] Show layout status")
        print("  [7] Scan CS3+ for registered locos (MFX auto-discovery)")
        print("  [Q] Quit")
        print()
        choice = input("  Choice: ").strip().upper()

        if choice == "1":
            routes = list(layout.routes.keys())
            if not routes:
                print("  No routes defined in layout.yaml")
                continue
            route_id = routes[0]
            train_ids = list(layout.trains.keys())
            print(f"\n  Starting route '{layout.routes[route_id].name}'")
            print(f"  Trains: {[layout.trains[t].name for t in train_ids]}")
            await engine.start(route_id, train_ids)
            print("  Automation running — press Ctrl+C or choose Stop to halt.")

        elif choice == "2":
            print("\n  !! EMERGENCY STOP !!")
            await engine.stop_all()

        elif choice == "3":
            await cs3.resume_all()
            print("  Track power resumed.")

        elif choice == "4":
            addr_str = input("  DCC address: ").strip()
            speed_str = input("  Speed step (0–128): ").strip()
            try:
                addr = int(addr_str)
                speed = int(speed_str)
                await cs3.set_loco_speed(addr, speed)
                print(f"  Loco {addr} → speed {speed}")
            except ValueError:
                print("  Invalid input.")

        elif choice == "5":
            sigs = list(layout.signals.values())
            for i, s in enumerate(sigs, 1):
                print(f"  [{i}] {s.name} (addr {s.dcc_address})")
            idx_str = input("  Signal number: ").strip()
            color = input("  [R]ed or [G]reen: ").strip().upper()
            try:
                sig = sigs[int(idx_str) - 1]
                if color == "R":
                    await cs3.set_signal_red(sig.dcc_address)
                    print(f"  {sig.name} → RED")
                elif color == "G":
                    await cs3.set_signal_green(sig.dcc_address)
                    print(f"  {sig.name} → GREEN")
            except (IndexError, ValueError):
                print("  Invalid selection.")

        elif choice == "6":
            print("\n  Block occupancy:")
            for block in layout.blocks.values():
                status = block.occupied_by if block.occupied_by else "free"
                kind = "STATION" if block.is_station else "block "
                print(f"    {kind} {block.name:<30} [{status}]")

        elif choice == "7":
            await _scan_locos(cs3)

        elif choice == "Q":
            await engine.stop_all()
            print("  Goodbye!")
            break


async def async_main(config_path: str):
    layout = load_layout(config_path)

    cs3 = CS3PlusClient(layout.cs3_ip, layout.cs3_port)
    ok = await cs3.connect()
    if not ok:
        print(f"\nERROR: Could not connect to CS3+ at {layout.cs3_ip}:{layout.cs3_port}")
        print("Check that:")
        print("  • Your Mac is on the same Wi-Fi (or Ethernet) as the CS3+")
        print("  • The IP address in config/layout.yaml is correct")
        print("     → Find it on the CS3+: Menu → Settings → Network → IP Address")
        print("  • The CS3+ is powered on\n")
        sys.exit(1)

    notify("Connected", f"CS3+ at {layout.cs3_ip} — layout loaded")
    engine = AutomationEngine(layout, cs3)

    try:
        await interactive_menu(engine, cs3, layout)
    except KeyboardInterrupt:
        print("\n  Stopping all trains...")
        await engine.stop_all()
    finally:
        await cs3.disconnect()


def main():
    parser = argparse.ArgumentParser(description="DCC Train Layout Controller")
    parser.add_argument(
        "--config",
        default=os.path.join(os.path.dirname(__file__), "..", "config", "layout.yaml"),
        help="Path to layout.yaml",
    )
    args = parser.parse_args()
    asyncio.run(async_main(args.config))


if __name__ == "__main__":
    main()
