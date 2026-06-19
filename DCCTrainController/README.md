# DCC Train Layout Controller
**Märklin CS3+ · HO Scale · Automatic Operation**

Runs on macOS or Windows. Controls your DCC trains through the Märklin CS3+
over your home Wi-Fi network — no cables from your computer to the track.

---

## What it does

- Moves trains automatically around a route you define
- Stops at every station platform for a configurable dwell time
- Controls your two signals: red when a block is occupied, green when clear
- Knows each train's DCC address, physical length (mm), and stopping distance
- Block occupancy via s88 sensors (or timed estimation if you don't have sensors yet)

---

## Hardware you need

| Item | Purpose |
|---|---|
| Märklin CS3+ | DCC command station — your trains already use this |
| s88 feedback modules | Detect which block a train is in (one contact per block) |
| Isolated track sections | One per block — cut both rails at each block boundary |
| Mac or PC | Runs this software, connected to same Wi-Fi as CS3+ |

> **No s88 sensors yet?** Set `USE_TIMED_BLOCKS = True` in `src/automation.py`.
> The engine will estimate positions from speed and time. Less precise, but works
> while you're still building the layout.

---

## Quick start

### 1. Install Python (3.11 or newer)
- Mac: `brew install python` or download from python.org
- Windows: download from python.org (tick "Add to PATH")

### 2. Install dependencies
```bash
cd DCCTrainController
pip install -r requirements.txt
```

### 3. Find your CS3+ IP address
On the CS3+: **Menu → Settings → Network → IP Address**

### 4. Edit `config/layout.yaml`
- Set the CS3+ IP address
- Add your trains with their DCC addresses and lengths in mm
- Define your blocks (track sections) with their s88 sensor numbers
- Define your routes (which blocks connect in sequence)

> **DCC address note:** Factory default is address 3 — always reprogram locos
> away from 3 before adding them here. Use addresses 1, 2, 4, 5, 6, 7 … etc.

### 5. Run
```bash
python -m src.main
```

---

## Measuring your layout

Use millimeters for everything — it's the most precise for model trains.

| What to measure | Where to put it in config |
|---|---|
| Each track section (block) | `blocks[].length_mm` |
| Each platform usable length | `blocks[].platform_length_mm` |
| Each train's total length (all cars + loco) | `trains[].length_mm` |
| How far before a station to start braking | `trains[].decel_distance_mm` |

The software uses `platform_length_mm` to verify a train will fit before stopping there.
If a train is longer than the platform, it will be flagged in the log.

---

## Layout YAML reference

```yaml
trains:
  - id: "train_1"
    name: "My ICE"
    dcc_address: 1        # programmed DCC address (not 3!)
    length_mm: 450        # measure nose to tail with all cars
    max_speed_step: 80    # 0–128 DCC speed steps
    decel_distance_mm: 300

blocks:
  - id: "block_A"
    name: "Main Station"
    length_mm: 600
    is_station: true
    platform_length_mm: 550
    s88_address: 1        # s88 contact number (1-based)

signals:
  - id: "signal_1"
    name: "East Signal"
    dcc_address: 101      # DCC accessory address
    protects_block: "block_A"
```

---

## Extending the layout later

When your layout is finished:
1. Add new blocks to `config/layout.yaml`
2. Wire s88 sensors for each new block
3. Add the blocks to a route in order
4. Restart the software — no code changes needed

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Cannot reach CS3+" | Check IP in layout.yaml; CS3+ and Mac/PC on same Wi-Fi |
| Train overshoots station | Increase `decel_distance_mm` for that train |
| Train stops too early | Decrease `decel_distance_mm` |
| Signal stays red | Check DCC accessory address matches CS3+ programming |
| s88 not detecting | Check wiring; verify address in CS3+ s88 setup menu |
