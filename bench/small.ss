$ bench_small

% base
id n++
...
created_at +
updated_at +

# base user
name s64 *
email s128 *
password_hash s255 *

# base post
title s255 *
body S *
author_id n *
status s16 *

# base comment
body S *
author_id n *
post_id n *
