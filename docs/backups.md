# Backups and restore verification

## The claim this section exists to avoid

"Backups are configured" is not a recovery plan. A backup that has never produced a restored, booting system is a hypothesis. I ran green backup jobs for weeks that excluded the single most important volume on the fleet, and the jobs reported success the whole time, because they did exactly what they were configured to do.

## Layout

Two scheduled jobs writing to **different physical disks**, so losing one disk does not lose both the data and its archive.

| Job | Guests | Target disk |
|---|---|---|
| A | application containers | disk 1 |
| B | dashboard, low-value containers | disk 2 |

This is not off-site. A fire, a theft, or a controller failure takes both copies. Stated plainly because "cross-disk" reads like redundancy and only covers single-disk failure.

## The exclusion trap

Check what a job **includes**, not whether it succeeded:

```bash
vzdump --help                      # confirm flags for your version
grep -r 'exclude' /etc/vzdump.conf /etc/pve/jobs.cfg
pct config <vmid> | grep -E '^mp[0-9]'
```

A mount point marked `backup=0` is skipped. That is often correct for bulk media and catastrophic for anything holding a database.

On restore, an excluded mount point is **recreated empty at its full declared size**. The guest boots, the services start, the data is gone. On thin-provisioned storage the empty volume also counts against the pool, and a few of them can overcommit it. Confirm overrun protection is on before you learn this during an actual recovery.

## Restore verification

The procedure lives in [`../backup/restore-test.md`](../backup/restore-test.md). Run it after any change to the jobs, and at least quarterly.

Two rules learned the hard way:

- **A restore test validates the job its subject belongs to, and nothing else.** When the test subject moved between jobs, the test kept passing and quietly stopped covering the job that mattered. Every job needs its own run.
- **Every size expectation dies with its subject.** Archive sizes, restore durations, and free-space requirements are per-guest. Retarget the test and the old numbers are void, not approximate.
