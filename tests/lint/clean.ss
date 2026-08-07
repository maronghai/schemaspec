$ lint_test
; Clean schema — no lint issues expected

% base
id n++
...
created_at d
updated_at d

; Users table
# base users : User accounts
name s
email s

; Orders table
# base orders : Customer orders
user_id n
total p
