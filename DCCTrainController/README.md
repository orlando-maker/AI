# DCC Train Layout Controller
**Märklin CS3+ · HO Scale · macOS · Automatic Operation**

Controls your DCC trains through the Märklin CS3+ over your home network —
your Mac connects to the CS3+ via Wi-Fi or Ethernet, and the CS3+ drives the track.
No cables from your Mac to the layout.

---

## How to run it

### First time setup

1. **Install Python 3** (if you don't have it):
   - Open Terminal (`Cmd + Space` → type "Terminal")
   - Type `python3 --version` and press Enter
   - If it says "command not found": download Python from [python.org](https://python.org) (3.11 or newer)

2. **Set your CS3+ IP address** in `config/layout.yaml`:
   ```yaml
   cs3_plus:
     ip: "192.168.1.100"   # ← change this
   ```
   Find the IP on your CS3+: **Menu → Settings → Network → IP Address**

3. **Run it:**
   ```bash
   ./run.sh
   ```
   That's it. The script sets up a virtual environment and installs dependencies automatically on the first run.

### Every time after that

```bash
./run.sh
```

Or open Terminal, drag the `DCCTrainController` folder onto it, and press Enter after `cd `, then run `./run.sh`.

---

## Network connection: Wi-Fi vs Ethernet

**Either works.** Your Mac connects to the CS3+ over your home network.

| Option | How | Notes |
|---|---|---|
| **Wi-Fi** | CS3+ connects to your router wirelessly | No cables — most convenient |
| **Ethernet** | Run a cable from CS3+ to your router | More reliable, no dropouts |

A LAN cable is only needed if you plug the CS3+ directly into your router. If your router is far from the layout, Wi-Fi is fine for model trains — the commands are tiny.

---

## What the menu does

```
  [1] Start automatic operation (all trains)
  [2] Stop all trains (emergency stop)
  [3] Resume after emergency stop
  [4] Set individual loco speed
  [5] Control a signal manually
  [6] Show layout status
  [7] Scan CS3+ for registered locos (MFX auto-discovery)
  [Q] Quit
```

Start with **[7]** to see all locos the CS3+ knows about, then **[1]** to run them automatically.

You'll also get macOS notifications on your Mac for key events (train arrivals, emergency stops).

---

## Hardware you need

| Item | Purpose |
|---|---|
| Märklin CS3+ | DCC command station — connects to your Mac over Wi-Fi or Ethernet |
| s88 feedback modules | Detect which block a train is in (one contact per block section) |
| Isolated track sections | One per block — cut both rails at each block boundary |

> **No s88 sensors yet?** Set `USE_TIMED_BLOCKS = True` in `src/automation.py`.
> The engine estimates positions by speed × time while you're still building.
> Swap it back to `False` once you wire the sensors.

---

## Setting up your locos

### MFX locos (most Märklin locos — the easy path)
1. Place the loco on the powered track
2. It self-registers with the CS3+ automatically within a few seconds
3. Run the software → choose **[7] Scan CS3+ for locos**
4. Copy the address shown into `config/layout.yaml`

### DCC locos (non-Märklin)
1. Program CV1 on the decoder to your chosen address — **never use address 3** (factory default)
2. Add it manually in the CS3+ loco database
3. Then **[7] Scan** will find it too

---

## Filling in config/layout.yaml

All measurements in **millimeters (mm)**.

| What to measure | YAML field |
|---|---|
| Each track section length | `blocks[].length_mm` |
| Each platform's usable length | `blocks[].platform_length_mm` |
| Each train nose-to-tail | `trains[].length_mm` |
| Braking distance before station | `trains[].decel_distance_mm` |

You can leave the example values in place and update them as your layout takes shape.
The software only needs the YAML file to change — no code edits required.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Could not connect to CS3+" | Check IP in layout.yaml; Mac and CS3+ on same network |
| Train overshoots station | Increase `decel_distance_mm` for that train |
| Train stops too early | Decrease `decel_distance_mm` |
| Signal stays red | Check DCC accessory address matches CS3+ programming |
| s88 not detecting | Check wiring; verify contact address in CS3+ s88 setup |
| No macOS notifications | System Settings → Notifications → Terminal → allow |
