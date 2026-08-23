; ── Compound FK: multi-column reference, full round-trip ──
$ demo

# users
id n++
org n
name s32

# memberships
user_id n
org_id n

> user_id org_id users.id users.org C
