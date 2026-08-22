$ schema

# users {
  id n++ PK
  name s100
}

# posts {
  id n++ PK
  user_id n -> users.id
  title s100
}
