$ naming_test utf8
; Schema for naming convention tests

# users : User accounts
id n++ : PK
userName s64 ='' : User name  // camelCase - should trigger
Email s64 ='' : Email  // PascalCase - should trigger
