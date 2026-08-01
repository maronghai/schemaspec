; ── Test: GraphQL FK references ──
$ demo

# users
id   n++
name s32

# orders
id      n++
user_id n
amount  m

> user_id users.id
