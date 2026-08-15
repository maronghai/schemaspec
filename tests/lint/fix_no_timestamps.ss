$ fix_test utf8
; Schema with no timestamps — lint --fix should add created_at/updated_at

; Events table
# events : Events
id n++ : PK
name s64 ='' : Event name
data S ='' : Event data
