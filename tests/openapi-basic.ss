$ myapp

# users
id n++
name s32 *
email s128 *
status e('active','inactive') = 'active'

# orders
id n++
user_id > users.id
amount m *
