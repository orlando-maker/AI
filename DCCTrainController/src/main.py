"""
DCC Train Layout Controller — macOS entry point.

Usage:
    ./run.sh
    python3 -m src.main
    python3 -m src.main --config config/layout.yaml
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

BANNER = """
╔══════════════════════════════════════════════════╗
║       DCC Train Layout Controller                ║
║       Märklin CS3+  ·  HO Scale  ·  macOS       ║
╚══════════════════════════════════════════════════╝"""


async def _scan_locos(cs3: CS3PlusClient):
    print("\n  Scanning CS3+ for registered locomotives…")
    locos = await cs3.discover_locos()
    if not locos:
        print("  No locos found. Place MFX locos on the powered track and try again.")
        return
    print(f"\n  {'#':<4} {'Name':<25} {'Protocol':<8} {'Address':<10} {'Speed':<7} Dir")
    print("  " + "─" * 62)
    for i, loco in enumerate(locos, 1):
        name      = loco.get("name", "—")[:24]
        protocol  = loco.get("protocol", "?").upper()
        address   = loco.get("address", loco.get("id", "?"))
        speed     = loco.get("speed", 0)
        direction = "FWD" if loco.get("direction", 1) else "REV"
        print(f"  {i:<4} {name:<25} {protocol:<8} {str(address):<10} {speed:<7} {direction}")
    print(f"\n  Total: {len(locos)} loco(s)")
    print("  Copy the address shown into config/layout.yaml for each train you want to automate.")


async def _live_status(engine: AutomationEngine):
    """Print a refreshing status board every 2 seconds."""
    print("\n  Live status (Ctrl+C to return to menu)\n")
    try:
        while True:
            lines = engine.status_lines()
            # Move cursor up and redraw
            up = f"\033[{len(lines)}A" if hasattr(_live_status, "_drawn") else ""
            _live_status._drawn = True
            sys.stdout.write(up)
            for line in lines:
                sys.stdout.write(f"\r\033[K{line}\n")
            sys.stdout.flush()
            await asyncio.sleep(2.0)
    except asyncio.CancelledError:
        pass


async def interactive_menu(engine: AutomationEngine, cs3: CS3PlusClient, layout):
    print(BANNER)
    print(f"\n  Connected to CS3+ at {layout.cs3_ip}")

    # Show which trains are autonomous vs manual
    auto_trains  = [t for t in layout.trains.values() if t.autonomous]
    manual_trains = [t for t in layout.trains.values() if not t.autonomous]
    if auto_trains:
        print(f"\n  Autopilot trains : {', '.join(t.name for t in auto_trains)}")
    if manual_trains:
        print(f"  Manual (you drive): {', '.join(t.name for t in manual_trains)}")

    status_task = None

    while True:
        print("\n" + "─" * 52)
        print("  [1] Start autopilot (all autonomous trains)")
        print("  [2] Emergency stop — all trains")
        print("  [3] Resume track power after emergency stop")
        print("  [4] Jog a single loco manually")
        print("  [5] Control a signal")
        print("  [6] Live status display")
        print("  [7] Scan CS3+ for registered locos")
        print("  [Q] Quit")
        print()

        choice = input("  Choice: ").strip().upper()

        if choice == "1":
            if status_task:
                status_task.cancel()
                status_task = None
            await engine.start_all()
            engine.start_watchers()
            names = [t.name for t in layout.trains.values() if t.autonomous]
            print(f"\n  Autopilot running: {', '.join(names)}")
            print("  Place any loco on its track — it will start automatically.")
            print("  Manual trains are unaffected — drive them from the CS3+ as normal.")

        elif choice == "2":
            if status_task:
                status_task.cancel()
                status_task = None
            print("\n  !! EMERGENCY STOP !!")
            await engine.stop_all()

        elif choice == "3":
            await cs3.resume_all()
            print("  Track power on.")

        elif choice == "4":
            trains = list(layout.trains.values())
            for i, t in enumerate(trains, 1):
                mode = "AUTO" if t.autonomous else "MANUAL"
                print(f"  [{i}] {t.name} (addr {t.dcc_address}, {mode})")
            try:
                idx  = int(input("  Train number: ").strip()) - 1
                spd  = int(input("  Speed step (0 = stop, 128 = full): ").strip())
                train = trains[idx]
                await cs3.set_loco_speed(train.dcc_address, spd)
                print(f"  {train.name} → speed {spd}")
            except (ValueError, IndexError):
                print("  Invalid input.")

        elif choice == "5":
            sigs = list(layout.signals.values())
            for i, s in enumerate(sigs, 1):
                print(f"  [{i}] {s.name} (addr {s.dcc_address})")
            try:
                sig   = sigs[int(input("  Signal number: ").strip()) - 1]
                color = input("  [R]ed or [G]reen: ").strip().upper()
                if color == "R":
                    await cs3.set_signal_red(sig.dcc_address)
                    print(f"  {sig.name} → RED")
                elif color == "G":
                    await cs3.set_signal_green(sig.dcc_address)
                    print(f"  {sig.name} → GREEN")
            except (IndexError, ValueError):
                print("  Invalid selection.")

        elif choice == "6":
            status_task = asyncio.create_task(_live_status(engine))
            try:
                await asyncio.wait_for(asyncio.shield(status_task), timeout=None)
            except (KeyboardInterrupt, asyncio.CancelledError):
                status_task.cancel()
                status_task = None
                print("\n  Returned to menu.")

        elif choice == "7":
            await _scan_locos(cs3)

        elif choice == "Q":
            if status_task:
                status_task.cancel()
            await engine.stop_all()
            print("\n  Goodbye!\n")
            break


async def async_main(config_path: str):
    layout = load_layout(config_path)
    cs3    = CS3PlusClient(layout.cs3_ip, layout.cs3_port)

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
        print("\n  Stopping all trains…")
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
