# Restore verification procedure

Proves an archive restores to a booting guest with real data in it. Run after any change to the backup jobs, and at least once a quarter.

**Each job needs its own run.** A pass here validates the job the subject belongs to and says nothing about the others.

## Before you start

| Requirement | Detail |
|---|---|
| Access | Interactive session on the hypervisor. Assume every `sudo` prompts. |
| Time | ~30 minutes, most of it the backup itself. |
| Free space | Archive target, plus the full restore target. |
| Subject | A low-value guest. If restoring it wrong costs nothing, you will actually run this. |
| Noise | Spinning disks are audible. Daytime only if the host shares a room. |

Open **one** session and stay in it. Running these as separate `ssh host 'command'` invocations re-prompts for a password each time.

## Procedure

```bash
# 1. Record what you expect to get back. Without this, step 6 has no baseline.
pct config <vmid>
pct exec <vmid> -- df -h /
pct exec <vmid> -- ls -la /path/that/should/contain/data

# 2. Fresh backup of the subject.
vzdump <vmid> --storage <archive-storage> --mode snapshot --compress zstd

# 3. Confirm the archive exists and note its size.
ls -lh /path/to/dump/vzdump-lxc-<vmid>-*.tar.zst

# 4. Restore to a NEW vmid. Never over the original.
pct restore <test-vmid> /path/to/dump/vzdump-lxc-<vmid>-*.tar.zst \
    --storage <restore-storage> \
    --hostname restore-test

# 5. Boot it. Leave it off the network if it runs anything that would
#    contend with the original for an IP, a share, or a database lock.
pct start <test-vmid>
pct exec <test-vmid> -- systemctl is-system-running --wait

# 6. Verify against step 1. This is the actual test.
pct exec <test-vmid> -- df -h /
pct exec <test-vmid> -- ls -la /path/that/should/contain/data
```

**Step 6 is the whole point.** A guest that boots proves the archive is not corrupt. It does not prove your data is in it. Compare against what you recorded in step 1 and look specifically at any path on a separate mount point, which is where exclusions hide.

## Cleanup

```bash
pct stop <test-vmid>
pct destroy <test-vmid> --purge
```

`--purge` also drops the test VMID from backup job definitions. Without it you leave a job pointed at a guest that no longer exists.

## Record

Write down, every run: the date, the subject, which job it covers, the archive size, the restore throughput, and **what was missing**. The last field is the one that matters, and it should be the reason you ran this at all.
