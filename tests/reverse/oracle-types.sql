CREATE TABLE products (
  id NUMBER(10) NOT NULL,
  name VARCHAR2(200) NOT NULL,
  price NUMBER(10, 2) NOT NULL,
  description CLOB,
  photo BLOB,
  is_active NUMBER(1) DEFAULT 1,
  PRIMARY KEY (id)
);
