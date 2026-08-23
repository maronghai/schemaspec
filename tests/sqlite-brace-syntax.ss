$ shop

# users {
id n++ PK
name s100
email s128 @u
}

# orders {
id n++ PK
user_id n -> users.id
amount m {>0}
}
