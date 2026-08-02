
CREATE TABLE "composite_pk" (
  "user_id" NUMBER(10) NOT NULL PRIMARY KEY,
  "role_id" NUMBER(10) NOT NULL PRIMARY KEY,
  "granted" TIMESTAMP NOT NULL
);
