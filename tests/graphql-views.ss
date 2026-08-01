; ── Test: GraphQL views ──
$ demo

# users
id   n++
name s32

& active_users = SELECT id, name FROM users WHERE active = 1
