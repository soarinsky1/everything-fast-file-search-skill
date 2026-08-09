# Token-efficient file discovery workflow

The skill is designed to reduce unnecessary agent context, not to replace every filesystem operation.

## Preferred sequence

1. Search through Everything.
2. Scope to the narrowest useful root.
3. Limit ordinary discovery to 20 results or fewer.
4. Use extension-specific searches when the existence of a file type matters.
5. Export structured candidates to CSV/JSON when another step will consume them.
6. Narrow candidates using path, filename, size, or metadata.
7. Hash only the final small set.
8. Read file contents only after discovery and identity narrowing.

## Avoid

- unbounded `Get-ChildItem -Recurse` over a large drive;
- returning hundreds or thousands of paths to the agent;
- hashing every large candidate before narrowing;
- interpreting a truncated result set as proof that another file type does not exist;
- interpreting Everything's sort order as semantic priority.

## Domain separation

This skill intentionally does not know what a "final model", "authoritative report", "production artifact", or other domain-specific role means.

A domain skill may consume this skill's candidate output and apply its own identity rules.
