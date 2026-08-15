$ fix_test utf8
; Schema with no primary key — lint --fix should add id n++

# logs : Log entries
timestamp d : Event timestamp
message s64 ='' : Log message
level s16 ='' : Log level
