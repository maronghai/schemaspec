# users
id n ! ?

# posts
id n ! ?
author_id
editor_id ?
tag_a n ?

> author_id users(id) -C
> (editor_id) users
> (tag_a) tags(a, b)