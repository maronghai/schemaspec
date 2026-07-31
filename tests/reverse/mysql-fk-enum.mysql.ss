# orders
id N ++ *
user_id *
total 16,2 *
status enum('pending','paid','shipped','done') * =pending
created_at t ++ *

@ idx_user (user_id)
> user_id users(id) -C