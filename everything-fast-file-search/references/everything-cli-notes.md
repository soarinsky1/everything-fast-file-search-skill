# Everything CLI notes

This skill uses voidtools `es.exe`, the command-line interface for Everything.

## Requirements

- Windows.
- Everything installed and running.
- `es.exe` available through PATH or at a known location.

## High-value ES options

- `-n <num>`: cap the number of results.
- `-path <path>`: constrain search to a path and its descendants.
- `-parent <path>` / `-parent-path <path>`: parent-based restrictions.
- `-p` / `-match-path`: match the full path and filename.
- `-r` / `-regex`: regex mode.
- `/a-d`: files only.
- `/ad`: folders only.
- `-sort <field[-ascending|-descending]>`: sort by path/name/size/date-modified/etc.
- `-full-path-and-name`: request full path output.
- `-cp 65001`: emit UTF-8 native output; pair with UTF-8 stdout decoding.
- `-size`, `-dm`: display size/date-modified columns when using ES output formats.
- `-csv`, `-json`: structured stdout formats.
- `-export-csv <file>`, `-export-json <file>`: structured export.
- `-timeout <ms>`: IPC/database wait timeout.
- `-no-result-error`: return exit code 9 when there are no results.
- `-version`: ES version.
- `-get-everything-version`: Everything version.

## Important exit codes

- `0`: success.
- `4`: missing option argument.
- `5`: export file creation failed.
- `6`: unknown switch.
- `7`: failed to send IPC query.
- `8`: ES could not obtain usable Everything IPC. A missing/inaccessible window,
  instance mismatch, or a database-ready wait expiring may lead to this code.
  Do not infer that Everything is stopped from the exit code alone.
- `9`: no results when `-no-result-error` is used.

## Search design

Use this progression:

1. exact distinctive token + root + extension + `-n 5`;
2. remove one constraint at a time;
3. only then broaden to `-n 20`;
4. do not dump hundreds/thousands of names into the model context.

Everything search syntax can also express wildcards, boolean operators, `ext:`, `size:`, and date filters. Keep complex Everything syntax in the query string only when it materially reduces candidates.

## Error 8 evidence

The official ES source `_es_find_ipc_window` checks database readiness when
`-timeout` is nonzero. A version-only probe without that timeout and an actual
search are not equivalent health checks. Keep timeout and retry limits bounded;
retain native error text and elapsed time when reporting failure.

Source repository: https://github.com/voidtools/ES (see `src/es.c`).

Sandbox IPC visibility must be checked through the host tool's approval mechanism,
as described in SKILL.md. No process restart or administrator-token launch is
implied by that check.
