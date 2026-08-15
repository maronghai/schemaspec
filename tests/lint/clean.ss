$ lint_test utf8
; Minimal clean schema for lint testing

# users : User table
id n++ : PK
created_at t =CURRENT_TIMESTAMP : Record creation time
updated_at t =CURRENT_TIMESTAMP : Record update time
