# The VPN exit node that ate 40% of my download speed

**Symptom:** 491 Mbps down on an 800/40 plan. Upload fine at 41. Ping fine at 10 ms.
**Cause:** my desktop was routing all internet traffic through a VPN container on my own LAN, auto-selected as an exit node. I never chose it.
**Time to find:** about two hours, most of it spent on the wrong things.

## What it looked like

Steam downloads were slow on every game. That is the detail that sent me down the wrong path first, because "slow on Steam" reads like a CDN problem, and I spent real time there before checking anything else.

The numbers that mattered:

| Measure | Value |
|---|---|
| Plan | 800 down / 40 up |
| Measured down | 491 Mbps |
| Measured up | 41 Mbps |
| Ping | 10 ms |

## What I ruled out, and why that was still worth doing

Everything host-side was already correct from an earlier tuning pass, and I confirmed it rather than assuming:

- Energy Efficient Ethernet off, Reduce Speed On Power Down off, NIC power management off
- 1 Gbps link negotiated, RSS on with 2 queues
- TCP autotuning `normal`, RSC on, MTU 1500
- Ultimate Performance power plan
- No Steam bandwidth limit, no Delivery Optimization job, nothing else competing

I eliminated the modem by specification instead of by swapping it. DOCSIS 3.1, 2.5 GbE port, rated by the ISP well past a gigabit. It cannot be the thing capping me at 491.

**That elimination is what made the real cause findable.** Once the client, the NIC, the modem, and the application were all accounted for, the only thing left was the path.

## The diagnostic that broke it open

```
tracert 1.1.1.1
```

Hop 1 was not my router. It was an address in `100.64.0.0/10`.

That range is CGNAT space, and my VPN assigns from it. So my traffic was entering the VPN before it ever reached the gateway. Confirmed on the client:

```
tailscale status
# active; exit node; direct <vpn-container>:41641, tx 1.05 GB  rx 17.6 GB

tailscale debug prefs
# "RouteAll": true
# "AutoExitNode": "any"
```

`AutoExitNode: any` is the whole story. I had turned it on at some point, the client picked an exit node by itself, and it picked a container running on the hypervisor in the next room. **17.6 GB had already gone through it.**

Every byte I downloaded was being encrypted by the container, sent to me over the LAN, and decrypted. That container's WireGuard throughput was the ceiling. Not my ISP, not Steam, not the modem.

## Why the symptoms pointed there and I did not see it

Three tells, obvious in hindsight:

1. **Download capped, upload untouched.** The tunnel ceiling sat around 490 Mbps. My upload is 40. A 40 Mbps upload never comes close to the ceiling, so it looked perfect while download was mangled.
2. **Ping stayed normal.** A remote exit node would have added latency and I would have caught it in a day. This one was ten feet away on the same switch, so latency barely moved.
3. **The first hop was wrong.** Nobody runs `tracert` when a download is slow. I should.

A local exit node buys nothing, which is what makes it so easy to miss. Same ISP line, same public IP, no privacy gain, no geographic change. All cost, no benefit.

## The fix

```
tailscale set --exit-node=
```

That clears `AutoExitNode` with it. Status flipped from `exit node` to `offers exit node`, and `tracert` hop 1 went back to being my router.

## Measurement mistake worth repeating

My first instinct was to verify with a scripted download:

```powershell
Invoke-WebRequest -Uri $url -OutFile $out
```

**That measurement is worthless here.** Runs lasted 1 to 2 seconds, which is entirely TCP slow start, and it returned 215 to 303 Mbps both before and after the fix. Identical numbers for a fixed and unfixed connection.

Two more traps in the same attempt:

- PowerShell's progress bar throttles the transfer it is measuring. `$ProgressPreference = 'SilentlyContinue'` or your result is about console rendering.
- Cloudflare's `__down` test endpoint returns 403 above roughly 100 MB, so the long run you need is the run you cannot have.

Single-connection transfers do not measure a multi-hundred-megabit line. Use a multi-connection speed test.

## What I changed about how I work

**Check the path before tuning the endpoint.** I tuned a NIC that was already correct while the actual problem was two layers up in routing. `tracert` takes four seconds and I ran it two hours in.

**A feature you enabled once is still enabled.** `AutoExitNode` was not an attack or a bug. It was a setting I turned on, forgot, and never audited. The config drift was mine.

**Watch for capped-download-with-fine-upload.** That asymmetry specifically means something in the path has a throughput ceiling your upload never reaches. It is a signature, not a coincidence.
