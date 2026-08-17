$ testdb

# user

id n++ = 0
name s32 = ''


created_at t
updated_at t# order

id n++ = 0
user_id n = 0
amount m = 0

> user_id user.id -C C

created_at t
updated_at t