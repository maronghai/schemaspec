$ base = id n ++ / name s / created_at t

# post
... base
title s

# comment
... base
post_id n @fk(post.id)
body s
