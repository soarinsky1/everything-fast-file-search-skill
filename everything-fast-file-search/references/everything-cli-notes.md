# Everything CLI notes

This skill uses the official Everything command-line interface (`es.exe`).

## Core options used by the skill

- `-path <path>`: limit search to a root and its descendants;
- `-n <num>`: limit displayed results;
- `-full-path-and-name`: emit one full path per result;
- `/a-d`: files only;
- `/ad`: folders only.

Everything search syntax can be supplied as search text terms, including `ext:` filters.

## Return code used for automatic recovery

`8` means the Everything IPC window was not found. The skill interprets this as a readiness problem, not as proof that the requested file does not exist.

When Error 8 occurs:

1. check whether `Everything.exe` is already running;
2. if it is not running and can be located, start it;
3. retry IPC briefly;
4. do not terminate or restart an already-running Everything process;
5. report failure if IPC still does not recover.

## PowerShell 5.1 argument construction

Keep independent Everything search terms as separate native arguments.

Correct conceptual shape:

```text
es.exe [options] basename ext:inp
```

Do not construct:

```text
es.exe [options] "basename ext:inp"
```

The second form can return zero results under Windows PowerShell 5.1 even when the GUI finds matching files.
