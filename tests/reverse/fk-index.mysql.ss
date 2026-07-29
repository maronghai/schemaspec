# user
id n ++ *
name s128 *
email

# order
id n ++ *
order_no s64 *
user_id @
amount 16,2 *

> user_id user.id