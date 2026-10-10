# Machine profile: <key>

> One file per machine: `config/machines/<key>.md`, where `<key>` is what
> `bash core/scripts/machine-key.sh` prints on that machine. The session start reads it
> and prints one line (`core/scripts/machine-profile.sh`).
>
> IDENTITY ONLY. Write what no tool can read: what the operator calls this machine, what
> it is for, which sender id its shared-memory entries carry, paths nothing can discover.
> Never write which programs or versions are installed — that is state; the session start
> measures it live from `config/machines/probe-tools.txt` (one command name per line).
> A copied tool table goes stale on the next install and then contradicts the machine.

- Alias:
- Role:
- Sender id:
- Session pull: on

## Paths nothing can discover

- (for example a media drive, a sync root, a backup target; "none" is an answer)

## Notes

- (anything that holds only on this machine)
