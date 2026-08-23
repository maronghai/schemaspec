# users
id INT ! ? -- [score:50]

# posts
id INT ! ? -- [score:50]
author_id INT -- [score:58]
editor_id INT ? -- [score:58]
tag_a INT ? -- [score:55]

> author_id users(id) -C
> (editor_id) users
> (tag_a) tags(a, b)